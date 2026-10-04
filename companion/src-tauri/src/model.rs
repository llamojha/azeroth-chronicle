use crate::savedvars::{Key, Value};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EventKind {
    SessionStarted,
    QuestAccepted,
    QuestCompleted,
    LocationChanged,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Event {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: EventKind,
    pub timestamp: u64,
    pub character_id: String,
    pub quest_id: Option<u64>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub objectives_text: Option<String>,
    pub zone: Option<String>,
    pub subzone: Option<String>,
    pub map_id: Option<u64>,
    pub level: Option<u64>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Character {
    pub id: String,
    pub name: String,
    pub realm: String,
    pub race: String,
    pub class: String,
    pub level: u64,
    pub events: Vec<Event>,
}

#[derive(Debug, Default)]
pub struct Validated {
    pub characters: BTreeMap<String, Character>,
    pub dropped: usize,
}

fn text(value: &Value, field: &str) -> Option<String> {
    value
        .field(field)?
        .text()
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}
fn number(value: &Value, field: &str) -> Option<u64> {
    value.field(field)?.integer()
}

fn event(value: &Value, character_id: &str) -> Option<Event> {
    let kind = match text(value, "type")?.as_str() {
        "session_started" => EventKind::SessionStarted,
        "quest_accepted" => EventKind::QuestAccepted,
        "quest_completed" => EventKind::QuestCompleted,
        "location_changed" => EventKind::LocationChanged,
        _ => return None,
    };
    if let Some(id) = value.field("characterId") {
        if id.text() != Some(character_id) {
            return None;
        }
    }
    let quest_id = number(value, "questId").filter(|n| *n > 0);
    if matches!(kind, EventKind::QuestAccepted | EventKind::QuestCompleted) && quest_id.is_none() {
        return None;
    }
    let timestamp = number(value, "timestamp").filter(|n| *n > 0 && *n <= 253_402_300_799)?;
    Some(Event {
        id: text(value, "id")?,
        kind,
        timestamp,
        character_id: character_id.into(),
        quest_id,
        title: text(value, "title"),
        description: text(value, "description"),
        objectives_text: text(value, "objectivesText"),
        zone: text(value, "zone"),
        subzone: text(value, "subzone"),
        map_id: number(value, "mapId"),
        level: number(value, "level"),
    })
}

pub fn validate(root: &Value) -> Result<Validated, String> {
    if root.field("schemaVersion").and_then(Value::integer) != Some(1) {
        return Err(
            "Unsupported schemaVersion; supported versions: 1. Existing history is unchanged."
                .into(),
        );
    }
    let Some(Value::Table(characters)) = root.field("characters") else {
        return Err("Expected characters table".into());
    };
    let mut result = Validated::default();
    for (key, value) in characters {
        let character = (|| {
            let Key::Name(id) = key else {
                return None;
            };
            if id.is_empty() {
                return None;
            }
            let Some(Value::Table(raw_events)) = value.field("events") else {
                return None;
            };
            let mut character = Character {
                id: id.clone(),
                name: text(value, "name")?,
                realm: text(value, "realm")?,
                race: text(value, "race")?,
                class: text(value, "class")?,
                level: number(value, "level").filter(|n| *n > 0)?,
                events: Vec::new(),
            };
            for (key, raw) in raw_events {
                if matches!(key, Key::Index(_)) {
                    if let Some(event) = event(raw, id) {
                        character.events.push(event);
                        continue;
                    }
                }
                result.dropped += 1;
            }
            character
                .events
                .sort_by(|a, b| (a.timestamp, &a.id).cmp(&(b.timestamp, &b.id)));
            Some(character)
        })();
        match character {
            Some(c) => {
                result.characters.insert(c.id.clone(), c);
            }
            None => result.dropped += 1,
        }
    }
    Ok(result)
}
