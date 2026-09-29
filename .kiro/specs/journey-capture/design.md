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
Stable given the same inputs, which is what makes companion import idempotent.

### Location change (meaningful only)
Keep `lastZone`/`lastSubzone` in memory. On a zone event, read current
zone/subzone; emit `location_changed` only if the pair differs from the last
emitted pair. This satisfies R4.1/R4.2 without coordinate polling.

### Quest snapshot resolution
```
pending = {}                         -- questId -> true
QUEST_ACCEPTED(questId):
    snap = tryResolve(questId)
    if snap.complete: store quest_accepted event
    else: pending[questId] = true
QUEST_LOG_UPDATE:
    for questId in pending:
        snap = tryResolve(questId)
        if snap.complete or firstAttemptStale:
            store quest_accepted event; pending[questId] = nil
```
`tryResolve` reads title/description/objectives with guarded API calls; any
field may be nil (R3.4).

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
