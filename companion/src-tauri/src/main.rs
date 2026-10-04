// Prevent a second console window on Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    #[cfg(feature = "desktop")]
    chronicle::desktop::run();
    #[cfg(not(feature = "desktop"))]
    eprintln!("Build the window with `npm run tauri:dev` / `npm run tauri:build` (they enable the `desktop` feature).");
}
