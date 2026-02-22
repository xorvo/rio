use std::process::{Child, Command};
use std::sync::Mutex;
use std::time::Duration;
use tauri::Manager;

struct PhoenixServer {
    process: Option<Child>,
    port: u16,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let port = portpicker::pick_unused_port().expect("No available port");
            let server = start_phoenix_server(app, port)?;

            app.manage(Mutex::new(PhoenixServer {
                process: Some(server),
                port,
            }));

            // Wait for Phoenix to be ready, then navigate to it
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                wait_for_server(port);

                if let Some(window) = handle.get_webview_window("main") {
                    let url = format!("http://localhost:{}", port);
                    let _ = window.eval(&format!("window.location.replace('{}')", url));
                }
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                if let Some(state) = window.try_state::<Mutex<PhoenixServer>>() {
                    if let Ok(mut server) = state.lock() {
                        if let Some(ref mut process) = server.process {
                            let _ = process.kill();
                            let _ = process.wait();
                        }
                        server.process = None;
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn start_phoenix_server(app: &tauri::App, port: u16) -> Result<Child, Box<dyn std::error::Error>> {
    let resource_dir = app
        .path()
        .resource_dir()
        .unwrap_or_else(|_| std::path::PathBuf::from("."));

    // The Phoenix release is bundled at <resources>/sidecar/bin/desktop
    let release_bin = resource_dir.join("sidecar").join("bin").join("desktop");

    if release_bin.exists() {
        // Production: run the bundled Elixir release
        eprintln!("Starting Phoenix release on port {} from {:?}", port, release_bin);

        // The release needs RELEASE_ROOT to find its libs
        let release_root = resource_dir.join("sidecar");

        // Use a unique node name based on PID to avoid conflicts
        let node_name = format!("desktop_{}", std::process::id());

        let child = Command::new(&release_bin)
            .arg("start")
            .env("PORT", port.to_string())
            .env("WORK_TREE_DESKTOP", "true")
            .env("PHX_SERVER", "true")
            .env("RELEASE_ROOT", &release_root)
            .env("RELEASE_TMP", std::env::temp_dir().join("work_tree_release"))
            .env("RELEASE_NODE", &node_name)
            .spawn()?;

        Ok(child)
    } else {
        // Development fallback: use the shell script
        let script = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("scripts")
            .join("run-phoenix.sh");

        eprintln!("Starting Phoenix via dev script: {:?} on port {}", script, port);

        let child = Command::new("bash")
            .arg("-l")
            .arg(&script)
            .env("PORT", port.to_string())
            .spawn()?;

        Ok(child)
    }
}

fn wait_for_server(port: u16) {
    let url = format!("http://localhost:{}", port);
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()
        .unwrap();

    for i in 0..60 {
        match client.get(&url).send() {
            Ok(resp) if resp.status().is_success() || resp.status().is_redirection() => {
                eprintln!("Phoenix ready on port {} (took ~{}s)", port, i / 2);
                return;
            }
            _ => {
                std::thread::sleep(Duration::from_millis(500));
            }
        }
    }

    eprintln!("Warning: Phoenix server did not respond on port {} within 30 seconds", port);
}
