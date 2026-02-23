# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Two-part tool for generating donor briefing documents for Northwestern:

1. **`prepSummaries.py`** — Python script that reads donor data from Excel, queries OpenAI to generate a biographical summary, and fills placeholders in a Word template to produce a briefing `.docx`.
2. **`nps_app/`** — Flutter desktop/web app intended as a UI front-end for the same workflow. Currently the "Generate File" button in `home_screen.dart` is a stub (`TODO` at line 97).

## Python Script

**Setup:** Requires a `.env` file in the root with `ChatGPT_API_KEY=<key>`.

**Run:**
```bash
pip install pandas python-docx openai python-dotenv
python prepSummaries.py
```

**How it works:**
- Reads `Briefing Data Pull Example.xlsx` (first row = target donor; all rows with same `Constituent: Donor ID` = recent contacts)
- Queries GPT-4.1-mini to web-search the donor and return structured JSON `{ found, biography: [string], sources }`
- Fills `{{placeholder}}` tokens in `Briefing_Template.docx` using `replace_everywhere()`, which handles placeholders split across Word XML runs
- Inserts biography bullet points at `{{bio_notes}}` via `insert_bio_notes()`
- Outputs `Generated_Briefing.docx`

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

**Add macOS support if missing:**
```bash
flutter create --platforms=macos .
```

**Architecture:**
- `lib/main.dart` — App entry point, `MaterialApp` with Material 3 theme (seed color `#1565C0`)
- `lib/screens/home_screen.dart` — Single-page UI: file picker (Excel), target name input, output folder picker, generate button. Persists last Excel path via `PrefsService`.
- `lib/screens/excel_viewer_screen.dart` — Full-screen Excel preview; renders each sheet as a scrollable `DataTable` using the `excel` package.
- `lib/services/prefs_service.dart` — Thin wrapper around `shared_preferences` to store/retrieve the last-used Excel file path.

**Key pending work:** `_generate()` in `home_screen.dart` is a placeholder. The actual briefing generation logic (currently in `prepSummaries.py`) needs to be wired in here.

## Template Placeholder Syntax

`Briefing_Template.docx` uses `{{snake_case}}` placeholders. The full mapping is defined in the `replacements` dict in `prepSummaries.py`. The special placeholder `{{bio_notes}}` is replaced with a list of bullet paragraphs rather than inline text.
