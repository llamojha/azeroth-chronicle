use chronicle::{
    discovery, importer,
    model::EventKind,
    savedvars,
    store::History,
    story::{JourneyContext, MockGenerator, StoryGenerator},
};
use proptest::prelude::*;
use std::fs;

const FIXTURE: &str = include_str!("fixtures/journey.lua");

#[test]
fn parses_real_serialization_shapes_and_escapes() {
    let value = savedvars::parse("-- data\n AzerothChronicleDB = { [\"x\"] = \"caf\\195\\169\\n\\\"\\\\\", flags={true,false,nil}, n=1e3 }").unwrap();
    assert_eq!(value.field("x").unwrap().text(), Some("café\n\"\\"));
    assert_eq!(value.field("n").unwrap().integer(), Some(1000));
}

#[test]
fn rejects_executable_and_ambiguous_lua() {
    for input in [
        "os.execute('touch bad')",
        "AzerothChronicleDB = setmetatable({}, {})",
        "AzerothChronicleDB = { x=function() end }",
        "AzerothChronicleDB = {}; print('bad')",
        "AzerothChronicleDB = {x=1,x=2}",
        "AzerothChronicleDB = {n=1e999}",
        "AzerothChronicleDB = {x=1+2}",
        "AzerothChronicleDB = {x=\"\\999\"}",
    ] {
        assert!(savedvars::parse(input).is_err(), "{input}");
    }
    assert!(savedvars::parse(&format!(
        "AzerothChronicleDB = {}{}",
        "{".repeat(100),
        "}".repeat(100)
    ))
    .is_err());
}

#[test]
fn missing_text_and_invalid_events_do_not_lose_valid_history() {
    let mut history = History::default();
    history.import(FIXTURE).unwrap();
    let bad_event = FIXTURE
        .replace("quest_completed", "unknown_type")
        .replace("id = \"accepted\"", "id = \"new\"");
    let report = history.import(&bad_event).unwrap();
    assert_eq!(report.dropped, 1);
    assert_eq!(history.characters["Player-fixture"].events.len(), 4);
    assert_eq!(
        history.characters["Player-fixture"]
            .events
            .iter()
            .find(|e| e.id == "complete")
            .unwrap()
            .description,
        None
    );
}

#[test]
fn existing_event_ids_are_immutable_and_conflicts_are_reported() {
    let mut history = History::default();
    history.import(FIXTURE).unwrap();
    let before = history.clone();
    let result = history
        .import(&FIXTURE.replace("A captured objective.", "changed"))
        .unwrap();
    assert_eq!(result.conflicts, 1);
    assert_eq!(history, before);
}

#[test]
fn unknown_schema_does_not_mutate_state() {
    let mut history = History::default();
    history.import(FIXTURE).unwrap();
    let before = history.clone();
    assert!(history.import(&FIXTURE.replace("= 1,", "= 2,")).is_err());
    assert_eq!(before, history);
}

#[test]
fn cache_round_trip_and_corruption_preservation() {
    let dir = tempfile::tempdir().unwrap();
    let cache = dir.path().join("history.json");
    let mut history = History::default();
    history.import(FIXTURE).unwrap();
    history.save(&cache).unwrap();
    assert_eq!(History::load(&cache).unwrap(), history);
    fs::write(&cache, "broken").unwrap();
    assert!(History::load(&cache).is_err());
    assert_eq!(fs::read_to_string(cache).unwrap(), "broken");
}

#[test]
fn discovers_multiple_accounts_and_preserves_bad_account_history() {
    let game = tempfile::tempdir().unwrap();
    let data = tempfile::tempdir().unwrap();
    let saved = game
        .path()
        .join("_classic_beta_/WTF/Account/TEST/SavedVariables");
    let other = game
        .path()
        .join("_classic_beta_/WTF/Account/BAD/SavedVariables");
    fs::create_dir_all(&saved).unwrap();
    fs::create_dir_all(&other).unwrap();
    let source = saved.join("AzerothChronicle.lua");
    fs::write(&source, FIXTURE).unwrap();
    fs::write(other.join("AzerothChronicle.lua"), "AzerothChronicleDB = {").unwrap();
    let before = fs::read(&source).unwrap();
    let found = discovery::discover(game.path()).unwrap();
    assert_eq!(found.files.len(), 2);
    assert!(found.checks.iter().all(|c| c.passed));
    let mut history = History::default();
    let cache = data.path().join("history.json");
    let first = importer::import_directory(&mut history, game.path(), &cache).unwrap();
    assert_eq!(first.imported_files, 1);
    assert_eq!(first.errors.len(), 1);
    let second = importer::import_directory(&mut history, game.path(), &cache).unwrap();
    assert_eq!(second.results[0].added, 0);
    assert_eq!(second.results[0].duplicates, 3);
    assert_eq!(fs::read(&source).unwrap(), before);
    assert_eq!(History::load(&cache).unwrap(), history);
    fs::write(&source, "AzerothChronicleDB = {").unwrap();
    let good = history.clone();
    let failed = importer::import_directory(&mut history, game.path(), &cache).unwrap();
    assert_eq!(failed.imported_files, 0);
    assert_eq!(history, good);
}

#[test]
fn failed_cache_write_does_not_publish_import() {
    let game = tempfile::tempdir().unwrap();
    let data = tempfile::tempdir().unwrap();
    let saved = game.path().join("WTF/Account/TEST/SavedVariables");
    fs::create_dir_all(&saved).unwrap();
    fs::write(saved.join("AzerothChronicle.lua"), FIXTURE).unwrap();
    let mut history = History::default();
    assert!(importer::import_directory(&mut history, game.path(), data.path()).is_err());
    assert_eq!(history, History::default());
}

#[test]
fn context_and_offline_recap_keep_missing_text_honest() {
    let mut history = History::default();
    history.import(FIXTURE).unwrap();
    let context = JourneyContext::assemble(&history.characters["Player-fixture"]);
    assert!(context.character.events.is_empty());
    assert_eq!(context.quest_snapshots.len(), 1);
    assert_eq!(context.events[0].kind, EventKind::LocationChanged);
    let story = MockGenerator.generate_story_so_far(&context).unwrap();
    assert!(story.contains("Offline recap"));
    assert!(story.contains("Hippogryph Harassment"));
    assert!(story.contains("Missing quest text is unavailable"));
}

proptest! {
    #[test]
    fn n_imports_are_idempotent(n in 1usize..50) {
        let mut history = History::default();
        for _ in 0..n { history.import(FIXTURE).unwrap(); }
        prop_assert_eq!(history.characters["Player-fixture"].events.len(),3);
    }
    #[test]
    fn truncated_save_never_mutates_history(cut in 0usize..FIXTURE.len()-2) {
        let mut history = History::default(); history.import(FIXTURE).unwrap(); let prior = history.clone();
        prop_assert!(history.import(&FIXTURE[..cut]).is_err()); prop_assert_eq!(history,prior);
    }
    #[test]
    fn timeline_is_ordered_and_stable(times in prop::collection::vec(1u64..100000,1..100)) {
        let mut text=String::from("AzerothChronicleDB={schemaVersion=1,characters={p={name='x',realm='r',race='r',class='c',level=1,events={");
        for (i,t) in times.iter().enumerate() { text.push_str(&format!("{{id='e{i}',type='session_started',timestamp={t}}},")); }
        text.push_str("}}}}");
        let mut history=History::default(); history.import(&text).unwrap();
        let events=&history.characters["p"].events;
        prop_assert!(events.windows(2).all(|w| (w[0].timestamp,&w[0].id)<=(w[1].timestamp,&w[1].id)));
    }
    #[test]
    fn arbitrary_input_does_not_panic(input in ".{0,2048}") { let _=savedvars::parse(&input); }
}
