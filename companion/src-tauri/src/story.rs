use crate::model::{Character, Event, EventKind};
use serde::Serialize;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JourneyContext {
    pub character: Character,
    pub events: Vec<Event>,
    pub quest_snapshots: Vec<Event>,
    pub total_events: usize,
}

impl JourneyContext {
    pub fn assemble(character: &Character) -> Self {
        let mut ordered = character.events.clone();
        ordered.sort_by(|a, b| (a.timestamp, &a.id).cmp(&(b.timestamp, &b.id)));
        let events: Vec<_> = ordered
            .iter()
            .rev()
            .take(100)
            .cloned()
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect();
        // Include the most recent earlier acceptance for each completion, never a future acceptance.
        let mut quest_snapshots: Vec<Event> = Vec::new();
        for completed in events
            .iter()
            .filter(|e| e.kind == EventKind::QuestCompleted)
        {
            if let Some(snapshot) = ordered.iter().rev().find(|e| {
                e.kind == EventKind::QuestAccepted
                    && e.quest_id == completed.quest_id
                    && (e.timestamp, &e.id) <= (completed.timestamp, &completed.id)
            }) {
                if !quest_snapshots.iter().any(|e| e.id == snapshot.id) {
                    quest_snapshots.push(snapshot.clone());
                }
            }
        }
        let mut metadata = character.clone();
        metadata.events.clear();
        Self {
            character: metadata,
            events,
            quest_snapshots,
            total_events: ordered.len(),
        }
    }
}

pub trait StoryGenerator {
    fn generate_story_so_far(&self, context: &JourneyContext) -> Result<String, String>;
}

pub struct MockGenerator;
impl StoryGenerator for MockGenerator {
    fn generate_story_so_far(&self, context: &JourneyContext) -> Result<String, String> {
        if context.events.is_empty() {
            return Err("Import journey events before generating a recap.".into());
        }
        let mut lines = vec![format!(
            "Offline recap of {}'s captured journey ({} of {} events).",
            context.character.name,
            context.events.len(),
            context.total_events
        )];
        for e in &context.events {
            let quest = e.title.clone().unwrap_or_else(|| {
                format!(
                    "quest {} (title not captured)",
                    e.quest_id.unwrap_or_default()
                )
            });
            let fact = match e.kind {
                EventKind::SessionStarted => "Started a play session.".into(),
                EventKind::QuestAccepted => format!("Accepted {quest}."),
                EventKind::QuestCompleted => {
                    format!("Completed quest {}.", e.quest_id.unwrap_or_default())
                }
                EventKind::LocationChanged => format!(
                    "Visited {}{}.",
                    e.zone.as_deref().unwrap_or("an unrecorded zone"),
                    e.subzone
                        .as_ref()
                        .map(|s| format!(" / {s}"))
                        .unwrap_or_default()
                ),
            };
            lines.push(format!("{}: {fact}", e.timestamp));
        }
        lines.push(
            "Missing quest text is unavailable; acceptance alone does not establish completion."
                .into(),
        );
        Ok(lines.join("\n"))
    }
}
