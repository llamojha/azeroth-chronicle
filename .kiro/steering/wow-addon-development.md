---
inclusion: fileMatch
fileMatch:
  - "addon/**"
  - ".kiro/specs/journey-capture/**"
---

# WoW Addon Development (Forever)

Guidance for the `addon/` side. Applies when editing the Lua addon or the
journey-capture spec.

## Sandbox reality

- Addons **cannot** write arbitrary files. Persistence is ONLY via
  `SavedVariables`, written by the client on `/reload`, logout, or clean exit.
- No network, no timers beyond `C_Timer`, no external processes. The addon
  OBSERVEs, NORMALIZEs, STOREs — nothing else.
- Never claim realtime sync. Data lands in the file only when WoW flushes it.

## `.toc` essentials

```
## Interface: <build interface number>
## Title: Azeroth Chronicle
## Notes: Personal memory for your character.
## SavedVariables: AzerothChronicleDB
AzerothChronicle.lua
```

Account-level `SavedVariables` (NOT `SavedVariablesPerCharacter`) — one
predictable file, characters keyed inside it.

## Event lifecycle

Register via a frame + `RegisterEvent` + `OnEvent` dispatch. Relevant events:

- `PLAYER_LOGIN` / `PLAYER_ENTERING_WORLD` — identify character, init DB.
- `QUEST_ACCEPTED` — capture quest; metadata may not be ready yet.
- `QUEST_LOG_UPDATE` — resolve pending quest snapshots.
- `QUEST_TURNED_IN` (or `QUEST_COMPLETE`) — quest completion.
- `ZONE_CHANGED` / `ZONE_CHANGED_NEW_AREA` / `ZONE_CHANGED_INDOORS` — location.

## Quest snapshot strategy

`QUEST_ACCEPTED` does not guarantee title/description are available. Pattern:

```
QUEST_ACCEPTED -> remember questId as pending
attempt resolution (GetQuestLogTitle / quest APIs)
if incomplete -> wait for QUEST_LOG_UPDATE, then resolve
persist the resolved snapshot as an immutable event
```

Store the text captured at play time; do not rely on fetching historical quest
text later.

## API discipline

- Prefer documented, Forever-compatible APIs. Do NOT invent APIs.
- Location: `GetZoneText()`, `GetSubZoneText()`, `C_Map.GetBestMapForUnit("player")`.
- Character: `UnitName`, `GetRealmName`, `UnitRace`, `UnitClass`, `UnitLevel`,
  `UnitGUID`.
- Guard every optional field; missing metadata must never crash the addon.

## Event identity & idempotency

Every event has a stable id: `<guid>:<type>:<questId|zone>:<timestamp>`.
Re-importing the same file must produce no duplicates on the companion side.

## Testing

Normalization logic (id building, snapshot assembly, dedup keys) should be
testable with fixtures independent of the live client.
