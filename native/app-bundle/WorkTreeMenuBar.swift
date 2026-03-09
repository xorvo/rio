import AppKit
import Foundation

// MARK: - Entry point

@main
struct WorkTreeMenuBarApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var serverProcess: Process?
    private var healthTimer: Timer?
    private var isServerRunning = false
    private var settingsWindow: NSWindow?

    private var port: Int {
        get { UserDefaults.standard.object(forKey: "port") as? Int ?? 4949 }
        set { UserDefaults.standard.set(newValue, forKey: "port") }
    }

    private var dataDir: String {
        get {
            UserDefaults.standard.string(forKey: "dataDir")
                ?? NSHomeDirectory() + "/Library/Application Support/WorkTree"
        }
        set { UserDefaults.standard.set(newValue, forKey: "dataDir") }
    }

    private var sidecarBin: String {
        let bundle = Bundle.main.bundlePath
        return bundle + "/Contents/Resources/sidecar/bin/desktop"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startServer()
        startHealthCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthTimer?.invalidate()
        stopServer()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeStatusImage(running: false)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if isServerRunning {
            let status = NSMenuItem(title: "Running on port \(port)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else {
            let status = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open in Browser", action: #selector(openInBrowser), keyEquivalent: "o")
        openItem.target = self
        openItem.isEnabled = isServerRunning
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Work Tree", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeStatusImage(running: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circleRect = NSRect(x: 4, y: 4, width: 10, height: 10)
            let path = NSBezierPath(ovalIn: circleRect)
            if running {
                NSColor.systemGreen.setFill()
                path.fill()
            } else {
                NSColor.secondaryLabelColor.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            return true
        }
        image.isTemplate = !running
        return image
    }

    // MARK: - Server lifecycle

    private func startServer() {
        let fm = FileManager.default
        let tmpDir = dataDir + "/tmp"

        try? fm.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sidecarBin)
        process.arguments = ["daemon"]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
            "HOME": NSHomeDirectory(),
            "PORT": String(port),
            "WORK_TREE_DESKTOP": "true",
            "WORK_TREE_DATA_DIR": dataDir,
            "PHX_SERVER": "true",
            "RELEASE_TMP": tmpDir,
            "RELEASE_NODE": "desktop_\(ProcessInfo.processInfo.processIdentifier)",
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Failed to start server: \(error)")
        }
    }

    private func stopServer() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sidecarBin)
        process.arguments = ["stop"]

        let tmpDir = dataDir + "/tmp"
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin",
            "HOME": NSHomeDirectory(),
            "RELEASE_TMP": tmpDir,
            "RELEASE_NODE": "desktop_\(ProcessInfo.processInfo.processIdentifier)",
        ]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Failed to stop server: \(error)")
        }

        // Clean up tmp dir
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    // MARK: - Health check

    private func startHealthCheck() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }

    private func checkHealth() {
        guard let url = URL(string: "http://localhost:\(port)") else { return }

        let request = URLRequest(url: url, timeoutInterval: 2.0)
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            let running: Bool
            if let http = response as? HTTPURLResponse {
                running = (200...499).contains(http.statusCode)
            } else {
                running = false
            }

            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isServerRunning != running {
                    self.isServerRunning = running
                    if let button = self.statusItem.button {
                        button.image = self.makeStatusImage(running: running)
                    }
                    self.rebuildMenu()
                }
            }
        }
        task.resume()
    }

    // MARK: - Actions

    @objc private func openInBrowser() {
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Work Tree Settings"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        // Port label + field
        let portLabel = NSTextField(labelWithString: "Port:")
        portLabel.frame = NSRect(x: 20, y: 140, width: 80, height: 22)
        contentView.addSubview(portLabel)

        let portField = NSTextField(frame: NSRect(x: 110, y: 140, width: 120, height: 22))
        portField.stringValue = String(port)
        portField.tag = 1
        contentView.addSubview(portField)

        // Data dir label + field
        let dirLabel = NSTextField(labelWithString: "Data directory:")
        dirLabel.frame = NSRect(x: 20, y: 105, width: 90, height: 22)
        contentView.addSubview(dirLabel)

        let dirField = NSTextField(frame: NSRect(x: 110, y: 105, width: 280, height: 22))
        dirField.stringValue = dataDir
        dirField.tag = 2
        contentView.addSubview(dirField)

        // Note
        let note = NSTextField(wrappingLabelWithString: "Changes take effect after restarting Work Tree.")
        note.frame = NSRect(x: 20, y: 60, width: 370, height: 30)
        note.textColor = .secondaryLabelColor
        note.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(note)

        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings(_:)))
        saveButton.frame = NSRect(x: 310, y: 20, width: 80, height: 30)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func saveSettings(_ sender: NSButton) {
        guard let contentView = sender.window?.contentView else { return }

        if let portField = contentView.viewWithTag(1) as? NSTextField {
            if let newPort = Int(portField.stringValue), (1...65535).contains(newPort) {
                port = newPort
            } else {
                let alert = NSAlert()
                alert.messageText = "Invalid port"
                alert.informativeText = "Port must be a number between 1 and 65535."
                alert.runModal()
                return
            }
        }

        if let dirField = contentView.viewWithTag(2) as? NSTextField {
            let newDir = dirField.stringValue
            if !newDir.isEmpty {
                dataDir = newDir
            }
        }

        sender.window?.close()
    }
}
