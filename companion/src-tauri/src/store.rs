use crate::{
    model::{self, Character, Event},
    savedvars,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashMap},
    io::Write,
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct History {
    pub characters: BTreeMap<String, Character>,
    pub selected_directory: Option<PathBuf>,
    pub last_import: Option<u64>,
}

#[derive(Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportResult {
    pub added: usize,
    pub duplicates: usize,
    pub dropped: usize,
    pub conflicts: usize,
}

impl History {
    /// Parsing/validation finish before any mutation. Existing IDs are immutable.
    pub fn import(&mut self, input: &str) -> Result<ImportResult, String> {
        let validated = model::validate(&savedvars::parse(input)?)?;
        let mut result = ImportResult {
            dropped: validated.dropped,
            ..Default::default()
        };
        let mut known: HashMap<String, Event> = self
            .characters
            .values()
            .flat_map(|c| &c.events)
            .map(|e| (e.id.clone(), e.clone()))
            .collect();
        for (id, mut incoming) in validated.characters {
            let mut events = self
                .characters
                .get(&id)
                .map(|c| c.events.clone())
                .unwrap_or_default();
            for event in incoming.events.drain(..) {
                if let Some(existing) = known.get(&event.id) {
                    if existing == &event {
                        result.duplicates += 1;
                    } else {
                        result.conflicts += 1;
                    }
                } else {
                    known.insert(event.id.clone(), event.clone());
                    events.push(event);
                    result.added += 1;
                }
            }
            events.sort_by(|a, b| (a.timestamp, &a.id).cmp(&(b.timestamp, &b.id)));
            incoming.events = events;
            self.characters.insert(id, incoming);
        }
        Ok(result)
    }

    pub fn load(cache: &Path) -> Result<Self, String> {
        match std::fs::read(cache) {
            Ok(bytes) => {
                let envelope: Cache = serde_json::from_slice(&bytes)
                    .map_err(|e| format!("Cache unreadable; file preserved: {e}"))?;
                if envelope.version != 1 {
                    return Err("Unsupported cache version; file preserved".into());
                }
                Ok(envelope.history)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(format!("Cannot read cache: {e}")),
        }
    }

    /// Atomic replacement in the companion's app-data directory, never WoW's directory.
    pub fn save(&self, cache: &Path) -> Result<(), String> {
        let parent = cache.parent().ok_or("Cache needs a parent directory")?;
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        let bytes = serde_json::to_vec(&Cache {
            version: 1,
            history: self.clone(),
        })
        .map_err(|e| e.to_string())?;
        let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
        file.write_all(&bytes).map_err(|e| e.to_string())?;
        file.as_file().sync_all().map_err(|e| e.to_string())?;
        file.persist(cache).map_err(|e| e.to_string())?;
        Ok(())
    }
}

#[derive(Serialize, Deserialize)]
struct Cache {
    version: u32,
    history: History,
}
