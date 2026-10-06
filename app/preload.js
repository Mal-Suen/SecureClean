const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('secureclean', {
  privacyScan: () => ipcRenderer.invoke('privacy-scan'),
  residueScan: () => ipcRenderer.invoke('residue-scan'),
  wipe: (paths) => ipcRenderer.invoke('wipe', paths),
  openPath: (p) => ipcRenderer.invoke('open-path', p),
  exportReport: (data) => ipcRenderer.invoke('export-report', data)
});
