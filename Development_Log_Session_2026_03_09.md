# Development Log — Session 2026-03-09

## Overview

Updated the Flutter app (`nps_app/`) to support the new FY26 briefing template, added multi-LLM provider support, implemented works cited with exact quotes, and fixed several bugs.

---

## 1. Field Mapping Analysis

**Goal:** Understand which Excel columns map to which fields in the new FY26 template.

**Files analyzed:**
- `Updated Data Pull Example.xlsx` — 24 columns, 2 data rows (same donor, different contact reports)
- `FY26_New_Briefing_Template_MailMerge.docx` — Word mail-merge template with MERGEFIELD complex fields

**Key findings:**
- Template uses Word MERGEFIELD complex fields (`fldChar begin` → `instrText MERGEFIELD` → `fldChar separate` → display text → `fldChar end`), NOT `{{placeholder}}` syntax
- 12 merge fields mapped to Excel columns
- `«Preferred_Mail_Name»` is static text embedded in a run (not a MERGEFIELD) — needs find-and-replace
- "Sample" bullets under BIOGRAPHICAL NOTES use `ListParagraph` style with `w:numPr` numbering
- `<<Contact Report Headline>>` and `<<<Contact report text>>` are placeholder paragraphs for contacts
- `Primary_Relationship_Manager_Name` has no Excel column — left empty
- Some field names are truncated in Word (e.g. `McCormick_Lifetime_New_Gifts__Comm_Cre`)

**Output:** Created `Field_Mapping.md` documenting the complete mapping.

---

## 2. Updated Flutter App to FY26 Template

**Goal:** Replace the old `{{placeholder}}` template logic with the new MERGEFIELD-based FY26 template.

### excel_service.dart — Complete rewrite of field mapping

**Before:** Returned `Map<String, String>` with `{{placeholder}}` keys (14 old fields like `{{meeting_type}}`, `{{lifetime_giving}}`, `{{recent_contacts}}`).

**After:**
- New `ContactEntry` class for structured contact report data (headline, date, body, author, purpose, method)
- `DonorData` now has `donorFirstName`, `mergeFields` (keyed by MERGEFIELD names), and `contacts` list
- 12 new merge field keys matching FY26 template exactly: `Donor_Name`, `All_Degrees`, `Primary_Employer_Name`, `Primary_Employment_Job_Title`, `Preferred_City`, `Preferred_State`, `Primary_Relationship_Manager_Name`, `University_Overall_Rating`, `Lifetime_New_Gifts__Comm_Credit`, `McCormick_Lifetime_New_Gifts__Comm_Cre`, `McCormick_Last_Gift_or_Pledge_Informatio`, `McCormick_Last_Gift_or_Pledge_Date`
- Removed old fields: `meeting_type`, `staff_name`, `meeting_platform`, `meeting_date`, `lifetime_giving`, `recent_gift_amount`, `recent_gift_date`, `contact_report_description`, `contact_report_date`, `recent_contacts`
- Changed giving fields: now uses `Lifetime New Gifts & Comm. Credit` (not `Lifetime Fundraising`) and McCormick-specific fields

### docx_service.dart — Complete rewrite for mail merge

Four distinct replacement strategies:

1. **MERGEFIELD replacement** — Walks each paragraph's child runs, finds `fldChar begin`→`instrText`→`fldChar separate`→display→`fldChar end` sequences. Extracts field name via regex on instrText, looks up value in mergeFields map, builds replacement run preserving the display run's formatting (rPr), removes the entire field sequence and inserts the new run. Recursively re-processes after each replacement since the runs list changes.

2. **Static text replacement** — For `«Preferred_Mail_Name»` (Unicode `\u00ab`/`\u00bb`). Joins all `w:t` text across runs in a paragraph, does string replacement, writes result to first text element and clears the rest.

3. **Bio notes** — Finds `ListParagraph`-styled paragraphs containing "Sample", captures their full `pPr` XML (including `w:numPr` for bullet numbering, spacing, font), removes them, inserts new paragraphs with the captured formatting.

4. **Contact reports** — Finds paragraphs containing "Contact Report Headline" and "Contact report text", captures the `SectionHeading` style pPr, removes placeholders, inserts real contact entries (headline + body paragraphs).

### generator_service.dart
- Updated template path to `assets/templates/FY26_Briefing_Template.docx`
- Passes new parameters: `mergeFields`, `contacts`, `donorFirstName`

### Asset
- Copied `FY26_New_Briefing_Template_MailMerge.docx` → `nps_app/assets/templates/FY26_Briefing_Template.docx`

---

## 3. Multi-LLM Provider Support

**Goal:** Let users choose between OpenAI, Google Gemini, and Anthropic Claude. Persist API keys per provider.

### New files created:

- **`llm_provider.dart`** — `LlmProvider` enum with `openai`, `gemini`, `claude`. Each has `displayName`, `keyHint` (text field placeholder like `sk-…`, `AIza…`, `sk-ant-…`), and `prefsKey` (SharedPreferences key for that provider's API key).

- **`gemini_service.dart`** — Calls `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent` with `google_search` grounding tool. API key passed as query parameter.

- **`claude_service.dart`** — Calls `https://api.anthropic.com/v1/messages` with `web_search_20250305` tool, model `claude-sonnet-4-6`. Uses `x-api-key` header and `anthropic-version: 2023-06-01`.

### Modified files:

- **`prefs_service.dart`** — `getApiKey`/`saveApiKey` now take `LlmProvider` parameter. Added `getSelectedProvider`/`saveSelectedProvider`. Each provider's key is stored under its own SharedPreferences key (`openai_api_key`, `gemini_api_key`, `claude_api_key`).

- **`generator_service.dart`** — Takes `LlmProvider provider` + generic `apiKey` instead of `openAiApiKey`. Routes to correct service via switch.

- **`home_screen.dart`** — New "AI Provider" section at top with `SegmentedButton<LlmProvider>`. Each provider has its own `TextEditingController`. Switching providers doesn't clear other keys. API key dialog title/hint updates to match selected provider. Status row shows whether active provider's key is configured.

---

## 4. Works Cited with Exact Quotes

**Goal:** Get the LLM to return exact quotes from sources, show what was read and how it informed each bullet. Add a WORKS CITED section to the end of the generated document.

### New files:

- **`bio_result.dart`** — `Citation` class (index, title, url, quote, detail) and `BioResult` class (biography list + citations list).

- **`bio_prompt.dart`** — Shared prompt template used by all three LLM services. Shared JSON parsing (`_parseJson` with fence stripping and fallback regex). `mergeCitations()` to de-duplicate API-level and JSON-level citations by URL.

### Prompt design (iterated twice):

**First attempt** — Asked for "one concise sentence, under 150 chars" per bullet. Result: LLM returned only directory-level contact info (phone, email, address) because the constraint was too tight.

**Final version:**
- Each bullet is 1-3 sentences covering a single topic
- Explicit rule: do NOT include contact info (phone, email, office address)
- Citation numbers `[1]`, `[2]` inline after claims
- Sources must include `"quote"` (exact verbatim text from the web page) and `"detail"` (how the quote informed the bio)
- "Try to cite every bullet" — not "omit if no citation" (which was too aggressive)

### Citation extraction from each provider:

**OpenAI:** Extracts `url_citation` annotations from `output[].content[].annotations[]`. Each has `url`, `title`, `start_index`, `end_index`.

**Gemini:** Extracts `groundingChunks[].web` from `candidates[0].groundingMetadata`. Each has `uri`, `title`.

**Claude:** Extracts `web_search_result` items from `web_search_tool_result` content blocks. Each has `url`, `title`, `page_content`. Truncates page_content to 300 chars for the detail field.

All three services merge JSON-parsed sources (which have index numbers matching bio text) with API-level citations, de-duplicated by URL.

### WORKS CITED section in docx_service.dart:

Appended at the very end of the document body (after Recent Contacts and trailing empty paragraphs). Format:

```
WORKS CITED (bold heading)

[1] Page Title (bold, 10pt)
     https://example.com/article (indented, 9pt)
     Quote: "exact verbatim text from the page" (indented, 9pt)
     Used for: how this informed the biography (indented, 9pt)

[2] ...
```

---

## 5. Bug Fix: macOS File Picker

**Problem:** Users couldn't click/select Excel files in the macOS file dialog — files appeared grayed out.

**Root cause:** `file_picker` package's `FileType.custom` with `allowedExtensions: ['xlsx', 'xls']` uses `NSOpenPanel.allowedContentTypes` on macOS, which requires proper UTType registration. Excel file UTTypes often don't map correctly, causing files to be unclickable.

**Fix:** Changed to `FileType.any` (lets user click any file) and validate the extension after selection:
```dart
final ext = p.extension(path).toLowerCase();
if (ext != '.xlsx' && ext != '.xls') {
  _showSnack('Please select an Excel file (.xlsx or .xls).');
  return;
}
```

---

## 6. Bug Fix: Bullet Points Not Rendering

**Problem:** Bio notes appeared as plain paragraphs without bullet markers in the generated Word document.

**Root cause:** The template's "Sample" paragraphs have specific XML that makes them bullets:
```xml
<w:numPr>
  <w:ilvl w:val="0"/>
  <w:numId w:val="1"/>
</w:numPr>
```
Plus font (`Akkurat Pro`), size (`20` half-points = 10pt), and spacing properties. The old code only set `<w:pStyle w:val="ListParagraph"/>` — missing `numPr` and all other formatting.

**Fix:** Before removing the "Sample" paragraphs, capture the full `pPr` XML (including numPr, spacing, font) and `rPr` XML (run-level formatting) from the first Sample paragraph. Replicate that exact XML on every new bio bullet paragraph.

---

## Files Changed (Summary)

### New files:
- `nps_app/assets/templates/FY26_Briefing_Template.docx`
- `nps_app/lib/services/llm_provider.dart`
- `nps_app/lib/services/gemini_service.dart`
- `nps_app/lib/services/claude_service.dart`
- `nps_app/lib/services/bio_result.dart`
- `nps_app/lib/services/bio_prompt.dart`
- `Field_Mapping.md`

### Modified files:
- `nps_app/lib/services/excel_service.dart` — new field mapping
- `nps_app/lib/services/openai_service.dart` — returns BioResult, extracts API citations
- `nps_app/lib/services/docx_service.dart` — MERGEFIELD replacement, bullet formatting, works cited
- `nps_app/lib/services/generator_service.dart` — multi-provider routing, passes citations
- `nps_app/lib/services/prefs_service.dart` — per-provider API keys
- `nps_app/lib/screens/home_screen.dart` — provider selector UI, file picker fix
- `CLAUDE.md` — updated project docs

### Documentation:
- `Field_Mapping.md` — complete Excel→template field mapping + implementation notes
- `CLAUDE.md` — updated to reflect FY26 template, all services, LLM providers
- `Development_Log_Session_2026_03_09.md` — this file

---

## Known Limitations / Future Work

1. **`Primary_Relationship_Manager_Name`** — No Excel column for this. Currently set to empty string. Could add a text input in the UI.
2. **Prompt tuning** — The biography prompt may need further iteration depending on which LLM provider is used. Different models interpret the prompt differently.
3. **Citation quality** — OpenAI's `url_citation` annotations give character-level offsets but they point into the raw JSON text, making bullet-level mapping impractical. Gemini's grounding supports have segment-level mapping that could theoretically be used. Currently we rely on the LLM to self-report inline `[1]` numbers.
4. **Template styles** — The Works Cited section uses hardcoded XML formatting rather than template-defined styles. If the template's font/color scheme changes, Works Cited may look inconsistent.
5. **file_picker** — Using `FileType.any` as a workaround for macOS UTType issues means the user sees all files, not just Excel. Could explore using `uniformTypeIdentifiers` directly if a future file_picker version fixes this.
