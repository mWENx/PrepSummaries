PrepSummaries — Donor Briefing Generator
A tool for generating personalized donor briefing documents for Northwestern, combining Excel donor data with AI-powered biographical research.

Overview
PrepSummaries automates the creation of two types of donor briefing documents:

Individual Briefings — Full one-page briefing per donor including biographical notes, giving history, contact reports, and relationship details
Event Briefings — Multi-donor event briefing sheets summarizing key attendees with biographical and giving information for meetings or events
How It Works
Upload Excel — Load a donor data pull (.xlsx) containing constituent information, giving history, and contact reports
Select Donors — Type to search and select one or more donors from the autocomplete field
AI Research — The app runs three parallel web searches per donor (career, education, personal), verifies sources, then synthesizes clean biographical bullet points
Document Generation — Fills a Word (.docx) mail-merge template with donor data and AI-generated bios, producing a formatted, print-ready briefing
Components
nps_app/ — Flutter desktop app (macOS) with full pipeline UI
prepSummaries.py — Legacy Python script (reference only)
Tech Stack
Frontend: Flutter / Dart (macOS desktop)
AI Providers: OpenAI (gpt-4.1-mini), Google Gemini (gemini-2.0-flash), Anthropic Claude (claude-sonnet-4-6) — switchable in settings
Document Generation: DOCX XML manipulation via archive + xml packages
Data: Excel parsing via the excel package
Setup

cd nps_app
flutter pub get
flutter run -d macos
Enter your API key for OpenAI, Gemini, or Claude in the app settings, then upload your donor Excel file to get started.
