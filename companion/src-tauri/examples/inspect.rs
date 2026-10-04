//! Read-only acceptance probe: no cache writes and no network calls.
use chronicle::{
    discovery::read_snapshot,
    store::History,
    story::{JourneyContext, MockGenerator, StoryGenerator},
};
fn main() -> Result<(), String> {
    let path = std::env::args()
        .nth(1)
        .ok_or("Pass a SavedVariables file path")?;
    let input = read_snapshot(std::path::Path::new(&path))?;
    let mut history = History::default();
    let first = history.import(&input)?;
    let second = history.import(&input)?;
    println!(
        "first_added={} second_added={} duplicates={} dropped={} conflicts={}",
        first.added, second.added, second.duplicates, first.dropped, first.conflicts
    );
    for character in history.characters.values() {
        let context = JourneyContext::assemble(character);
        let story = MockGenerator.generate_story_so_far(&context)?;
        println!(
            "events={} text_snapshots={} offline_recap_bytes={}",
            character.events.len(),
            character
                .events
                .iter()
                .filter(|e| e.description.is_some() && e.objectives_text.is_some())
                .count(),
            story.len()
        );
    }
    Ok(())
}
