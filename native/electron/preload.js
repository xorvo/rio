const { contextBridge } = require("electron");

// Expose minimal desktop API to the renderer.
// All app logic runs through Phoenix LiveView — no IPC needed.
contextBridge.exposeInMainWorld("desktop", {
  platform: process.platform,
});
