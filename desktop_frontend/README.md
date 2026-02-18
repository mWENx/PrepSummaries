# Desktop Frontend Scaffold

Basic Electron frontend for macOS and Windows.

- Default UI: file list of previously generated outputs.
- Alternative UI: same file list plus an `Add Excel File` button to select the workbook used for document generation.
- Simple UI: prompt flow for Excel source (upload or use last), person name input, and save-folder selection.

## Run

1. `cd desktop_frontend`
2. `npm install`
3. `npm start` (default UI), `npm run start:alt` (alternative UI), or `npm run start:simple` (simple UI)

The app scans the project root (`../`) and lists files that contain `generated` in the name or end with `.docx`, `.pdf`, or `.txt`.

In the alternative UI, selected Excel path is persisted to `desktop_frontend/app_state.json`.
