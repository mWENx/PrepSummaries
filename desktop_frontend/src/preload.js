const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('filesApi', {
  listGenerated: () => ipcRenderer.invoke('files:listGenerated'),
  openPath: (filePath) => ipcRenderer.invoke('files:openPath', filePath),
  selectExcel: () => ipcRenderer.invoke('files:selectExcel'),
  getSelectedExcel: () => ipcRenderer.invoke('files:getSelectedExcel'),
  getGenerationPrefs: () => ipcRenderer.invoke('files:getGenerationPrefs'),
  selectSaveDirectory: () => ipcRenderer.invoke('files:selectSaveDirectory')
});
