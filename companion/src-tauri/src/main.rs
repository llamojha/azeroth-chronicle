// Prevent a second console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    #[cfg(feature = "desktop")]
    chronicle::desktop::run();
    #[cfg(not(feature = "desktop"))]
    eprintln!("Build the window with `cargo tauri dev` / `--features desktop`.");
}
