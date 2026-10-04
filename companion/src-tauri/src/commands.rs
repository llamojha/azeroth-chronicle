//! Command orchestration layer.
//!
//! The Tauri `#[command]` handlers are thin wrappers that lock [`AppState`] and
//! delegate to the methods here, so the integration logic stays testable without
//! a Tauri runtime or a chosen frontend. State owns the imported [`History`] and
//! the companion's own app-data cache path; it never touches the WoW directory
//! except read-only through [`crate::discovery`]/[`crate::importer`].

use crate::{
    discovery::{self, Discovery},
    importer::{self, BatchResult},
    store::History,
    story::{JourneyContext, StoryGenerator},
};
use std::path::{Path, PathBuf};

/// Persistent companion state: the imported journey and where its cache lives.
pub struct AppState {
    pub history: History,
    pub cache: PathBuf,
}

impl AppState {
    /// Load prior history from the companion app-data cache. A missing cache is a
    /// clean first run, not an error (see [`History::load`]).
    pub fn load(cache: PathBuf) -> Result<Self, String> {
        Ok(Self {
            history: History::load(&cache)?,
            cache,
        })
    }

    /// R1.2/R1.3: validate a chosen WoW directory and locate `AzerothChronicle.lua`.
    /// Read-only; performs no import and mutates no state.
    pub fn discover(&self, selected: &Path) -> Result<Discovery, String> {
        discovery::discover(selected)
    }

    /// R2–R5: additive, idempotent import from the selected directory. A bad parse
    /// aborts without publishing, leaving prior history untouched.
    pub fn import(&mut self, selected: &Path) -> Result<BatchResult, String> {
        importer::import_directory(&mut self.history, selected, &self.cache)
    }

    /// Persist the chosen WoW directory as soon as it is selected, independent of a
    /// successful import. Discovery (R1.2/R1.3) is still the validation gate; this
    /// records the already-chosen folder so closing the app after discovery — or
    /// while troubleshooting an empty/malformed save — does not lose the selection.
    pub fn remember_directory(&mut self, selected: &Path) -> Result<(), String> {
        self.history.selected_directory = Some(selected.to_path_buf());
        self.history.save(&self.cache)
    }

    /// R6: the persisted history backing the timeline view and last-sync status.
    pub fn timeline(&self) -> &History {
        &self.history
    }

    /// R8: recap for one character, grounded only in that character's captured
    /// events. The generator is injected so the offline `MockGenerator` backs
    /// tests/demos and the Bedrock provider is swapped in only after consent.
    pub fn story_so_far(
        &self,
        character_id: &str,
        generator: &dyn StoryGenerator,
    ) -> Result<String, String> {
        let character = self
            .history
            .characters
            .get(character_id)
            .ok_or("Unknown character. Import a journey first.")?;
        let context = JourneyContext::assemble(character);
        generator.generate_story_so_far(&context)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::story::MockGenerator;

    const SAVE: &str = r#"
        AzerothChronicleDB = {
          schemaVersion = 1,
          characters = {
            ["Thrall-Durotan"] = {
              name = "Thrall", realm = "Durotan", race = "Orc",
              class = "Shaman", level = 12,
              events = {
                { id = "s1", type = "session_started", timestamp = 100, level = 1 },
                { id = "q1", type = "quest_accepted", timestamp = 200,
                  questId = 92516, title = "Hippogryph Harassment" },
                { id = "q1c", type = "quest_completed", timestamp = 300, questId = 92516 },
              },
            },
          },
        }
    "#;

    /// A selected directory containing the known WTF/Account/SavedVariables hierarchy,
    /// plus a sibling app-data dir for the cache (never inside the WoW tree).
    fn fixture(root: &Path, body: &str) -> (PathBuf, PathBuf) {
        let wow = root.join("WoW");
        let saved = wow
            .join("WTF")
            .join("Account")
            .join("ACCT")
            .join("SavedVariables");
        std::fs::create_dir_all(&saved).unwrap();
        std::fs::write(saved.join("AzerothChronicle.lua"), body).unwrap();
        let appdata = root.join("appdata");
        std::fs::create_dir_all(&appdata).unwrap();
        (wow, appdata.join("cache.json"))
    }

    #[test]
    fn import_is_idempotent_and_recap_is_grounded() {
        let tmp = tempfile::tempdir().unwrap();
        let (wow, cache) = fixture(tmp.path(), SAVE);
        let mut state = AppState::load(cache).unwrap();

        let first = state.import(&wow).unwrap();
        assert_eq!(first.imported_files, 1);
        assert_eq!(first.results[0].added, 3);
        assert_eq!(first.results[0].duplicates, 0);

        // Re-import the same save: nothing added, every event seen as a duplicate.
        let again = state.import(&wow).unwrap();
        assert_eq!(again.results[0].added, 0);
        assert_eq!(again.results[0].duplicates, 3);

        // Timeline reflects the single merged character.
        assert_eq!(state.timeline().characters.len(), 1);
        assert!(state.timeline().last_import.is_some());

        let recap = state
            .story_so_far("Thrall-Durotan", &MockGenerator)
            .unwrap();
        assert!(recap.contains("Thrall"));
        assert!(recap.contains("Hippogryph Harassment"));
    }

    #[test]
    fn selected_folder_persists_without_a_successful_import() {
        let tmp = tempfile::tempdir().unwrap();
        let (wow, cache) = fixture(tmp.path(), SAVE);

        // Choose the folder and persist it, but never import.
        {
            let mut state = AppState::load(cache.clone()).unwrap();
            state.remember_directory(&wow).unwrap();
            assert!(state.timeline().characters.is_empty());
            assert_eq!(state.timeline().last_import, None);
        }

        // Reopen the app: the selection survived, independent of any import.
        let reloaded = AppState::load(cache).unwrap();
        assert_eq!(
            reloaded.timeline().selected_directory.as_deref(),
            Some(wow.as_path())
        );
        assert!(reloaded.timeline().characters.is_empty());
    }

    #[test]
    fn story_for_unknown_character_is_rejected() {
        let tmp = tempfile::tempdir().unwrap();
        let (_wow, cache) = fixture(tmp.path(), SAVE);
        let state = AppState::load(cache).unwrap();
        assert!(state
            .story_so_far("Nobody-Nowhere", &MockGenerator)
            .is_err());
    }

    #[test]
    fn malformed_save_does_not_mutate_prior_history() {
        let tmp = tempfile::tempdir().unwrap();
        let (wow, cache) = fixture(tmp.path(), SAVE);
        let mut state = AppState::load(cache).unwrap();
        state.import(&wow).unwrap();
        let before = state.timeline().clone();

        // Overwrite the save with garbage and re-import: the file fails to parse,
        // so it is reported as an error, nothing is imported, and the in-memory
        // history is left exactly as it was (keep-last-good).
        let saved = wow
            .join("WTF")
            .join("Account")
            .join("ACCT")
            .join("SavedVariables")
            .join("AzerothChronicle.lua");
        std::fs::write(&saved, "AzerothChronicleDB = { this is not valid").unwrap();
        let report = state.import(&wow).unwrap();
        assert_eq!(report.imported_files, 0);
        assert_eq!(report.errors.len(), 1);
        assert_eq!(state.timeline(), &before);
    }
}
