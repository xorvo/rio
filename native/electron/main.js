const { app, BrowserWindow } = require("electron");
const { spawn } = require("child_process");
const http = require("http");
const path = require("path");
const fs = require("fs");

let phoenixProcess = null;
let mainWindow = null;

async function getAvailablePort() {
  // get-port is ESM-only, use dynamic import
  const { default: getPort } = await import("get-port");
  return getPort();
}

function getSidecarPath() {
  // Production: resources/sidecar/bin/desktop
  const resourcePath = process.resourcesPath || path.join(__dirname, "..");
  const releaseBin = path.join(resourcePath, "sidecar", "bin", "desktop");

  if (fs.existsSync(releaseBin)) {
    return { mode: "release", path: releaseBin };
  }

  // Development fallback: run-phoenix.sh
  const script = path.join(__dirname, "..", "scripts", "run-phoenix.sh");
  if (fs.existsSync(script)) {
    return { mode: "dev", path: script };
  }

  throw new Error(
    "No Phoenix sidecar or dev script found. Run 'make desktop-release' or check native/scripts/run-phoenix.sh"
  );
}

function startPhoenix(port) {
  const sidecar = getSidecarPath();

  const env = {
    ...process.env,
    PORT: String(port),
    WORK_TREE_DESKTOP: "true",
    PHX_SERVER: "true",
  };

  if (sidecar.mode === "release") {
    const releaseRoot = path.dirname(path.dirname(sidecar.path));
    const nodeName = `desktop_${process.pid}`;

    console.log(`Starting Phoenix release on port ${port} from ${sidecar.path}`);

    phoenixProcess = spawn(sidecar.path, ["start"], {
      env: {
        ...env,
        RELEASE_ROOT: releaseRoot,
        RELEASE_TMP: path.join(
          require("os").tmpdir(),
          "work_tree_release"
        ),
        RELEASE_NODE: nodeName,
      },
      stdio: "inherit",
    });
  } else {
    console.log(`Starting Phoenix via dev script on port ${port}`);

    phoenixProcess = spawn("bash", ["-l", sidecar.path], {
      env,
      stdio: "inherit",
    });
  }

  phoenixProcess.on("error", (err) => {
    console.error("Failed to start Phoenix:", err);
  });

  phoenixProcess.on("exit", (code) => {
    console.log(`Phoenix exited with code ${code}`);
    phoenixProcess = null;
  });
}

function waitForServer(port, timeoutMs = 30000) {
  const url = `http://localhost:${port}`;
  const interval = 500;
  const maxAttempts = Math.ceil(timeoutMs / interval);
  let attempts = 0;

  return new Promise((resolve, reject) => {
    const check = () => {
      attempts++;
      const req = http.get(url, (res) => {
        const status = res.statusCode;
        if (status >= 200 && status < 400) {
          console.log(
            `Phoenix ready on port ${port} (took ~${(attempts * interval) / 1000}s)`
          );
          res.resume();
          resolve();
        } else {
          res.resume();
          retry();
        }
      });

      req.on("error", retry);
      req.setTimeout(2000, () => {
        req.destroy();
        retry();
      });
    };

    const retry = () => {
      if (attempts >= maxAttempts) {
        reject(
          new Error(
            `Phoenix did not respond on port ${port} within ${timeoutMs / 1000}s`
          )
        );
      } else {
        setTimeout(check, interval);
      }
    };

    check();
  });
}

function createWindow(port) {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    title: "Work Tree",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // Show loading screen while Phoenix boots
  mainWindow.loadFile(path.join(__dirname, "loading.html"));

  waitForServer(port)
    .then(() => {
      mainWindow.loadURL(`http://localhost:${port}`);
    })
    .catch((err) => {
      console.error(err.message);
      // Still try to load — Phoenix may be partially ready
      mainWindow.loadURL(`http://localhost:${port}`);
    });

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

function killPhoenix() {
  if (phoenixProcess) {
    console.log("Killing Phoenix server...");
    // Kill the process group to catch child processes
    try {
      process.kill(-phoenixProcess.pid, "SIGTERM");
    } catch {
      // process.kill with negative PID may not work on all platforms
      phoenixProcess.kill("SIGTERM");
    }

    // Force kill after 5 seconds if still running
    setTimeout(() => {
      if (phoenixProcess) {
        try {
          process.kill(-phoenixProcess.pid, "SIGKILL");
        } catch {
          try {
            phoenixProcess.kill("SIGKILL");
          } catch {
            // already dead
          }
        }
      }
    }, 5000);

    phoenixProcess = null;
  }
}

app.whenReady().then(async () => {
  try {
    const port = await getAvailablePort();
    startPhoenix(port);
    createWindow(port);
  } catch (err) {
    console.error("Failed to start:", err);
    app.quit();
  }

  app.on("activate", () => {
    // macOS: re-create window when dock icon clicked with no windows
    if (BrowserWindow.getAllWindows().length === 0) {
      getAvailablePort().then((port) => createWindow(port));
    }
  });
});

app.on("before-quit", killPhoenix);

app.on("window-all-closed", () => {
  killPhoenix();
  // On macOS, apps typically stay active until Cmd+Q
  if (process.platform !== "darwin") {
    app.quit();
  }
});
