let selectedExcelPath = null;
let selectedSaveDirectory = null;

function showStatus(text, isError = false) {
  const status = document.getElementById('status');
  status.textContent = text;
  status.style.color = isError ? '#b03030' : '#1f6b2e';
}

function setExcel(pathValue) {
  selectedExcelPath = pathValue || null;
  document.getElementById('excel-value').textContent =
    selectedExcelPath || 'No Excel selected.';
}

function setSaveDirectory(pathValue) {
  selectedSaveDirectory = pathValue || null;
  document.getElementById('save-value').textContent =
    selectedSaveDirectory || 'No save folder selected.';
}

function submitIllustrativeRequest() {
  const personName = document.getElementById('person-input').value.trim();

  if (!selectedExcelPath) {
    showStatus('Select an Excel file first.', true);
    return;
  }

  if (!personName) {
    showStatus('Enter a person name.', true);
    return;
  }

  if (!selectedSaveDirectory) {
    showStatus('Choose a save folder.', true);
    return;
  }

  showStatus(
    `Ready: person="${personName}", excel="${selectedExcelPath}", saveTo="${selectedSaveDirectory}"`
  );
}

window.addEventListener('DOMContentLoaded', async () => {
  const prefs = await window.filesApi.getGenerationPrefs();
  setExcel(prefs?.selectedExcelPath || null);
  setSaveDirectory(prefs?.selectedSaveDirectory || null);

  document.getElementById('upload-excel').addEventListener('click', async () => {
    const result = await window.filesApi.selectExcel();
    if (result?.canceled) return;

    if (!result?.ok) {
      showStatus(result?.error || 'Unable to select Excel file.', true);
      return;
    }

    setExcel(result.selectedExcelPath);
    showStatus('Excel file selected.');
  });

  document.getElementById('use-last-excel').addEventListener('click', async () => {
    const prefsLatest = await window.filesApi.getGenerationPrefs();
    if (!prefsLatest?.selectedExcelPath) {
      showStatus('No previously selected Excel file found.', true);
      return;
    }

    setExcel(prefsLatest.selectedExcelPath);
    showStatus('Using last selected Excel file.');
  });

  document.getElementById('choose-save').addEventListener('click', async () => {
    const result = await window.filesApi.selectSaveDirectory();
    if (result?.canceled) return;

    if (!result?.ok) {
      showStatus(result?.error || 'Unable to select save folder.', true);
      return;
    }

    setSaveDirectory(result.selectedSaveDirectory);
    showStatus('Save folder selected.');
  });

  document.getElementById('enter-btn').addEventListener('click', submitIllustrativeRequest);

  document.getElementById('person-input').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      submitIllustrativeRequest();
    }
  });
});
