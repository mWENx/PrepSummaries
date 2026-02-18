const { app, BrowserWindow, ipcMain, shell, dialog } = require('electron');
const path = require('path');
const fs = require('fs/promises');

const TARGET_DIR = path.resolve(__dirname, '..', '..');
const APP_STATE_PATH = path.resolve(__dirname, '..', 'app_state.json');
const USE_ALT_UI = process.argv.includes('--alt-ui');
const USE_SIMPLE_UI = process.argv.includes('--simple-ui');

function createWindow() {
  const win = new BrowserWindow({
    width: 980,
    height: 680,
    minWidth: 760,
    minHeight: 520,
    title: 'Prep Summaries - Generated Files',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  const rendererDir = USE_SIMPLE_UI
    ? 'renderer_simple'
    : USE_ALT_UI
      ? 'renderer_alt'
      : 'renderer';
  win.loadFile(path.join(__dirname, rendererDir, 'index.html'));
}

async function listGeneratedFiles() {
  const entries = await fs.readdir(TARGET_DIR, { withFileTypes: true });

  const files = await Promise.all(
    entries
      .filter((entry) => entry.isFile())
      .filter((entry) => {
        const lower = entry.name.toLowerCase();
        return (
          lower.includes('generated') ||
          lower.endsWith('.docx') ||
          lower.endsWith('.pdf') ||
          lower.endsWith('.txt')
        );
      })
      .map(async (entry) => {
        const fullPath = path.join(TARGET_DIR, entry.name);
        const stats = await fs.stat(fullPath);

        return {
          name: entry.name,
          fullPath,
          sizeBytes: stats.size,
          modifiedAt: stats.mtime.toISOString()
        };
      })
  );

  files.sort((a, b) => new Date(b.modifiedAt) - new Date(a.modifiedAt));
  return files;
}

ipcMain.handle('files:listGenerated', async () => {
  try {
    return await listGeneratedFiles();
  } catch (error) {
    return {
      error: error.message || 'Failed to read generated files.'
    };
  }
});

ipcMain.handle('files:openPath', async (_event, filePath) => {
  try {
    if (typeof filePath !== 'string' || filePath.length === 0) {
      return { ok: false, error: 'Invalid file path.' };
    }

    const normalized = path.resolve(filePath);
    const relative = path.relative(TARGET_DIR, normalized);
    if (relative.startsWith('..') || path.isAbsolute(relative)) {
      return { ok: false, error: 'File is outside the allowed directory.' };
    }

    await fs.access(normalized);
    const openError = await shell.openPath(normalized);
    if (openError) {
      return { ok: false, error: openError };
    }

    return { ok: true };
  } catch (error) {
    return { ok: false, error: error.message || 'Failed to open file.' };
  }
});

async function readAppState() {
  try {
    const raw = await fs.readFile(APP_STATE_PATH, 'utf8');
    return JSON.parse(raw);
  } catch (_error) {
    return {};
  }
}

async function writeAppState(nextState) {
  await fs.writeFile(APP_STATE_PATH, JSON.stringify(nextState, null, 2), 'utf8');
}

ipcMain.handle('files:getSelectedExcel', async () => {
  const state = await readAppState();
  return {
    selectedExcelPath: state.selectedExcelPath || null,
    selectedExcelUpdatedAt: state.selectedExcelUpdatedAt || null
  };
});

ipcMain.handle('files:selectExcel', async () => {
  try {
    const result = await dialog.showOpenDialog({
      title: 'Choose an Excel file for document generation',
      properties: ['openFile'],
      filters: [
        { name: 'Excel Files', extensions: ['xlsx', 'xls', 'xlsm', 'csv'] }
      ]
    });

    if (result.canceled || result.filePaths.length === 0) {
      return { ok: false, canceled: true };
    }

    const selectedExcelPath = path.resolve(result.filePaths[0]);
    await fs.access(selectedExcelPath);

    const existing = await readAppState();
    const nextState = {
      ...existing,
      selectedExcelPath,
      selectedExcelUpdatedAt: new Date().toISOString()
    };
    await writeAppState(nextState);

    return { ok: true, ...nextState };
  } catch (error) {
    return { ok: false, error: error.message || 'Failed to select Excel file.' };
  }
});

ipcMain.handle('files:getGenerationPrefs', async () => {
  const state = await readAppState();
  return {
    selectedExcelPath: state.selectedExcelPath || null,
    selectedExcelUpdatedAt: state.selectedExcelUpdatedAt || null,
    selectedSaveDirectory: state.selectedSaveDirectory || null,
    selectedSaveDirectoryUpdatedAt: state.selectedSaveDirectoryUpdatedAt || null
  };
});

ipcMain.handle('files:selectSaveDirectory', async () => {
  try {
    const result = await dialog.showOpenDialog({
      title: 'Choose where generated files should be saved',
      properties: ['openDirectory', 'createDirectory']
    });

    if (result.canceled || result.filePaths.length === 0) {
      return { ok: false, canceled: true };
    }

    const selectedSaveDirectory = path.resolve(result.filePaths[0]);
    await fs.access(selectedSaveDirectory);

    const existing = await readAppState();
    const nextState = {
      ...existing,
      selectedSaveDirectory,
      selectedSaveDirectoryUpdatedAt: new Date().toISOString()
    };
    await writeAppState(nextState);

    return { ok: true, ...nextState };
  } catch (error) {
    return {
      ok: false,
      error: error.message || 'Failed to select save directory.'
    };
  }
});

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
