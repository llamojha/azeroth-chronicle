# Journey Capture — Design

## Pipeline

```
WoW events
    ↓
event adapters (per WoW event -> intent)
    ↓
normalizer (build immutable ChronicleEvent + stable id)
    ↓
store (append to AzerothChronicleDB.characters[guid].events, dedup by id)
    ↓
AzerothChronicleDB  --(client flush)-->  AzerothChronicle.lua
```

## Modules (single-file addon, logical sections)

The addon ships as one Lua file (`AzerothChronicle.lua`) for MVP simplicity,
organized into logical sections:

1. **DB bootstrap** — ensure `AzerothChronicleDB` exists with `schemaVersion=1`
   and a `characters` table; get-or-create the current character record.
2. **Identity** — resolve name/realm/race/class/level/guid from unit APIs.
3. **Event adapters** — one handler per WoW event that gathers raw data.
4. **Normalizer** — `MakeEvent(type, fields)` builds the id and the immutable
   record; `Location()` reads zone/subzone/mapId.
5. **Quest resolver** — pending-quest map; resolve on `QUEST_LOG_UPDATE`.
6. **Store** — `AppendEvent(charRecord, event)` with dedup by id.
7. **Dispatch** — frame + `RegisterEvent` + `OnEvent` switch.

## Data contracts

### Character record
```
{ name, realm, race, class, level, events = { ChronicleEvent, ... } }
```

### ChronicleEvent (normalized)
```
id           string   -- <guid>:<type>:<questId|zone>:<timestamp>
type         string   -- session_started | quest_accepted | quest_completed | location_changed
timestamp    number   -- unix seconds (time())
-- type-specific fields:
questId?     number
title?       string
description? string
objectivesText? string
zone?        string
subzone?     string
mapId?       number
level?       number   -- session_started
```

## Key algorithms

### Event id
```
id = guid .. ":" .. type .. ":" .. (questId or zone or "?") .. ":" .. timestamp
```
This is the base ID. For all supported events, MakeEvent copies the
captured fields and adds :2, :3, ... when the base already exists in the character
history. This preserves distinct same-second occurrences, including after reload.
The stored ID never changes, which makes companion import idempotent. Legacy
IDs remain unchanged. Quest occurrence guards run before allocating an ID.

### Location change (meaningful only)
Restore `lastZone`/`lastSubzone` from the latest stored location event on login,
then keep them in memory. On a zone event, read current
zone/subzone; emit `location_changed` only if the pair differs from the last
emitted pair. This satisfies R4.1/R4.2 without coordinate polling.

### Quest snapshot resolution
QUEST_DETAIL caches one quest offer by GetQuestID using GetTitleText,
GetQuestText, and GetObjectiveText. Viewing a dialog creates no event.
Acceptance copies and consumes a matching offer; the log reader fills gaps.

Acceptance saves questId, timestamp, zone, subzone, and mapId before trying
metadata resolution. A pending snapshot is not yet part of immutable history.
Resolution merges optional text into that snapshot, not into a stored event.

If immediate resolution fails, the next QUEST_LOG_UPDATE retries once and
stores the snapshot even if text is missing. PLAYER_LOGOUT flushes all pending
snapshots; turn-in flushes that quest before recording completion. This bounded
fallback preserves the occurrence but can miss text that arrives after the retry.

Repeated acceptance notifications are suppressed within one addon load until
removal or turn-in. QUEST_REMOVED flushes acceptance and allows reacceptance;
it never records completion. Completed quest IDs suppress repeated turn-ins
until a new acceptance, allowing separate same-second repeatable cycles.
These guards are runtime-only; cross-reload notification replay is unverified.

The Classic reader resolves a current index by quest ID and checks return 8
of GetQuestLogTitle before reading text. It saves the selected index, selects
the matched entry, reads GetQuestLogQuestText, then restores selection even on
read failure. Nested QUEST_LOG_UPDATE handling is paused during this operation.
C_QuestLog.GetQuestInfo is a guarded title fallback. Only nonempty strings are
stored as text. Published Classic source supports these contracts; the actual
Forever client passed the live acceptance gate on build 70170 (see task list).

## Failure modes & mitigations

| Failure | Mitigation |
|---|---|
| Quest metadata not ready at accept | defer to `QUEST_LOG_UPDATE` (R3.2) |
| Optional field nil | guarded reads; event still valid (R3.4, R7.1) |
| Duplicate zone events | dedup by last-emitted pair (R4.2) |
| Duplicate event ids | store dedups by id (R5.2) |
| Schema drift later | bump `schemaVersion`, keep data-parseable (R8) |

## Implementation phases

1. `.toc` + DB bootstrap + identity + dispatch skeleton (loads, no errors).
2. Location capture (meaningful transitions).
3. Quest accept + snapshot resolver.
4. Quest completion.
5. Session start event.
6. Normalization tests with fixtures.

## Testing approach

Extract pure functions (`MakeEventId`, `NormalizeQuest`, dedup key) so they can
be exercised with a Lua test runner + fixtures without the live client. Property
targets from the brief: serialize→parse preserves fields; N imports → 1 stored
event; missing optional metadata never fails.
