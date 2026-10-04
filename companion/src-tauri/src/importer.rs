use crate::{
    discovery,
    store::{History, ImportResult},
};
use serde::Serialize;
use std::{
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchResult {
    pub results: Vec<ImportResult>,
    pub errors: Vec<String>,
    pub imported_files: usize,
}

/// Invalid accounts do not prevent valid accounts importing. Persist before publishing memory.
/// The caller supplies an existing companion app-data directory, never a game directory.
pub fn import_directory(
    history: &mut History,
    selected: &Path,
    cache: &Path,
) -> Result<BatchResult, String> {
    let discovery = discovery::discover(selected)?;
    if discovery.files.is_empty() {
        return Err(
            "No AzerothChronicle.lua found. Enable the addon and /reload or log out of WoW.".into(),
        );
    }
    let root = selected.canonicalize().map_err(|e| e.to_string())?;
    let parent = cache.parent().ok_or("Invalid cache path")?;
    // Check before any write. App setup owns creation of its own data directory.
    if parent
        .canonicalize()
        .map_err(|e| e.to_string())?
        .starts_with(&root)
    {
        return Err("Companion cache must be outside the WoW installation".into());
    }
    let mut staged = history.clone();
    let mut report = BatchResult::default();
    for file in discovery.files {
        match discovery::read_snapshot(&file).and_then(|s| staged.import(&s)) {
            Ok(result) => {
                report.results.push(result);
                report.imported_files += 1;
            }
            Err(e) => report.errors.push(format!("{}: {e}", file.display())),
        }
    }
    if report.imported_files > 0 {
        staged.selected_directory = Some(root);
        staged.last_import = Some(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(|e| e.to_string())?
                .as_secs(),
        );
        staged.save(cache)?;
        *history = staged;
    }
    Ok(report)
}
