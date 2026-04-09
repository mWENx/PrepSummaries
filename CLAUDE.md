# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Two-part tool for generating donor briefing documents for Northwestern:

1. **`prepSummaries.py`** — Python script (legacy/reference). Reads donor data from Excel, queries OpenAI, fills a Word template. Uses the old `Briefing_Template.docx` with `{{placeholder}}` syntax.
2. **`nps_app/`** — Flutter desktop/web app (primary). Full pipeline: Excel parsing → OpenAI bio search → DOCX generation using the FY26 mail-merge template.

## Python Script (Legacy)

**Setup:** Requires a `.env` file in the root with `ChatGPT_API_KEY=<key>`.

**Run:**
```bash
pip install pandas python-docx openai python-dotenv
python prepSummaries.py
```

## Flutter App

**Location:** `nps_app/`

**Supported platforms:** macOS desktop, Chrome web (no Android/iOS target currently)

**Commands (run from `nps_app/`):**
```bash
flutter pub get
flutter run -d macos       # macOS desktop
flutter run -d chrome      # web
flutter analyze
flutter test               # runs nps_app/test/
```

**Architecture:**
- `lib/main.dart` — App entry point, `MaterialApp` with Material 3 theme (seed color `#1565C0`)
- `lib/screens/home_screen.dart` — Single-page UI: file picker (Excel), target name input, output folder picker, generate button. Persists last Excel path and API key via `PrefsService`.
- `lib/screens/excel_viewer_screen.dart` — Full-screen Excel preview; renders each sheet as a scrollable `DataTable` using the `excel` package.
- `lib/services/prefs_service.dart` — Thin wrapper around `shared_preferences` for last-used Excel path, per-provider API keys, and selected LLM provider.
- `lib/services/excel_service.dart` — Parses donor data from Excel → `DonorData` (merge fields map + structured contact entries).
- `lib/services/llm_provider.dart` — `LlmProvider` enum (openai, gemini, claude) with display names, key hints, prefs keys.
- `lib/services/openai_service.dart` — OpenAI Responses API (`gpt-4.1-mini` with `web_search_preview`).
- `lib/services/gemini_service.dart` — Gemini API (`gemini-2.0-flash` with `google_search` grounding).
- `lib/services/claude_service.dart` — Anthropic Messages API (`claude-sonnet-4-6` with `web_search_20250305`).
- `lib/services/docx_service.dart` — Unzips .docx, replaces Word MERGEFIELD complex fields, inserts bio notes and contact reports, rezips.
- `lib/services/generator_service.dart` — Async stream orchestrating the full pipeline.

**Template:** `assets/templates/FY26_Briefing_Template.docx` (FY26 mail-merge format)

**Data source:** `Updated Data Pull Example.xlsx`

## Template & Field Mapping

The FY26 template uses **Word MERGEFIELD complex fields** (not `{{placeholder}}` syntax). See `Field_Mapping.md` for the complete mapping between Excel columns and template fields.

**Key points:**
- 12 mail merge fields mapped from Excel columns (e.g. `Donor_Name`, `All_Degrees`, `University_Overall_Rating`)
- `Preferred_Mail_Name` is static text (not a MERGEFIELD) — replaced via text find-and-replace
- "Sample" bullets under BIOGRAPHICAL NOTES are replaced with AI-generated bio
- `<<Contact Report Headline>>` / `<<<Contact report text>>` placeholders are replaced with structured contact entries from Excel rows grouped by Donor ID
- `Primary_Relationship_Manager_Name` has no Excel column — left empty

## Packages (nps_app/pubspec.yaml)

file_picker, shared_preferences, excel, path, http, archive, xml
