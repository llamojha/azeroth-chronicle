//! Tauri desktop shell: thin `#[command]` wrappers that lock [`AppState`] and
//! delegate to the tested orchestration layer in [`crate::commands`]. All work is
//! read-only against the WoW folder; the only writes are to the companion's own
//! app-data cache. Commands are synchronous, so Tauri runs them off the UI thread.

use crate::{
    commands::AppState, discovery::Discovery, importer::BatchResult, store::History,
    story::MockGenerator,
};
use std::{path::Path, sync::Mutex};
use tauri::{Manager, State};

type Shared = Mutex<AppState>;

#[tauri::command]
fn discover(path: String, state: State<'_, Shared>) -> Result<Discovery, String> {
    state
        .lock()
        .map_err(|e| e.to_string())?
        .discover(Path::new(&path))
}

#[tauri::command]
fn import_journey(path: String, state: State<'_, Shared>) -> Result<BatchResult, String> {
    state
        .lock()
        .map_err(|e| e.to_string())?
        .import(Path::new(&path))
}

#[tauri::command]
fn timeline(state: State<'_, Shared>) -> Result<History, String> {
    Ok(state.lock().map_err(|e| e.to_string())?.timeline().clone())
}

#[tauri::command]
fn story_so_far(character_id: String, state: State<'_, Shared>) -> Result<String, String> {
    // Offline generator only. The Bedrock provider is wired in behind explicit
    // consent, never on this default path.
    state
        .lock()
        .map_err(|e| e.to_string())?
        .story_so_far(&character_id, &MockGenerator)
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            let state = AppState::load(dir.join("history.json")).map_err(std::io::Error::other)?;
            app.manage(Mutex::new(state));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            discover,
            import_journey,
            timeline,
            story_so_far
        ])
        .run(tauri::generate_context!())
        .expect("error while running Azeroth Chronicle");
}
