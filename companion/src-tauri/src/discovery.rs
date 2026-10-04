use crate::savedvars::MAX_BYTES;
use serde::Serialize;
use std::{
    fs,
    io::Read,
    path::{Path, PathBuf},
};

#[derive(Debug, Serialize)]
pub struct Check {
    pub label: String,
    pub passed: bool,
}
#[derive(Debug, Default, Serialize)]
pub struct Discovery {
    pub checks: Vec<Check>,
    pub files: Vec<PathBuf>,
}

fn children(path: &Path) -> Result<Vec<PathBuf>, String> {
    let mut paths = Vec::new();
    for entry in
        fs::read_dir(path).map_err(|e| format!("Cannot inspect {}: {e}", path.display()))?
    {
        let entry = entry.map_err(|e| e.to_string())?;
        if entry.file_type().map_err(|e| e.to_string())?.is_dir() {
            paths.push(entry.path());
        }
    }
    paths.sort();
    Ok(paths)
}

/// Accept a client directory or its parent. Search exactly the known hierarchy.
pub fn discover(selected: &Path) -> Result<Discovery, String> {
    let root = selected
        .canonicalize()
        .map_err(|e| format!("Cannot open selected folder: {e}"))?;
    let mut clients = vec![root.clone()];
    clients.extend(children(&root)?);
    let mut result = Discovery::default();
    for client in clients {
        let wtf = client.join("WTF");
        if !wtf.is_dir() {
            continue;
        }
        let account = wtf.join("Account");
        result.checks.push(Check {
            label: format!("{}: WTF", client.display()),
            passed: true,
        });
        result.checks.push(Check {
            label: format!("{}: Account", client.display()),
            passed: account.is_dir(),
        });
        if !account.is_dir() {
            continue;
        }
        let mut found_saved = false;
        for account in children(&account)? {
            let saved = account.join("SavedVariables");
            if !saved.is_dir() {
                continue;
            }
            found_saved = true;
            let path = saved.join("AzerothChronicle.lua");
            if path.is_file() {
                let canonical = path.canonicalize().map_err(|e| e.to_string())?;
                if !canonical.starts_with(&root) {
                    return Err("SavedVariables link leaves the selected installation".into());
                }
                result.files.push(canonical);
            }
        }
        result.checks.push(Check {
            label: format!("{}: SavedVariables", client.display()),
            passed: found_saved,
        });
    }
    if result.checks.is_empty() {
        for label in ["WTF", "Account", "SavedVariables"] {
            result.checks.push(Check {
                label: label.into(),
                passed: false,
            });
        }
    }
    result.files.sort();
    result.files.dedup();
    result.checks.push(Check {
        label: "AzerothChronicle.lua".into(),
        passed: !result.files.is_empty(),
    });
    Ok(result)
}

pub fn read_snapshot(path: &Path) -> Result<String, String> {
    let file = fs::File::open(path).map_err(|e| e.to_string())?;
    let before = file.metadata().map_err(|e| e.to_string())?;
    if !before.is_file() || before.len() > MAX_BYTES as u64 {
        return Err("Not a regular SavedVariables file within 32 MiB".into());
    }
    let mut bytes = Vec::new();
    file.take(MAX_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    let after = fs::metadata(path).map_err(|e| e.to_string())?;
    if bytes.len() > MAX_BYTES
        || before.len() != after.len()
        || bytes.len() as u64 != after.len()
        || before.modified().ok() != after.modified().ok()
    {
        return Err(
            "WoW is writing the save. Retry after the write finishes; history is unchanged.".into(),
        );
    }
    String::from_utf8(bytes).map_err(|_| "SavedVariables is not UTF-8".into())
}
