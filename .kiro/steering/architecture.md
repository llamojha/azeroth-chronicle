---
inclusion: always
---

# Architecture

SavedVariables are an ingestion boundary, not the canonical product database.

The desktop companion never writes to WoW files. Treat `AzerothChronicle.lua`
as read-only, external, untrusted input.

All imports must be idempotent.

Captured game data should be immutable whenever possible.

Events are preferred over mutable aggregate state.

External/AI systems consume normalized events rather than parsing WoW files
directly.

## Data flow

```
GAMEPLAY (WoW: Forever)
   ↓  addon: OBSERVE / NORMALIZE / STORE
AzerothChronicleDB (SavedVariables, account-level)
   ↓  companion: DISCOVER / READ / PARSE / VALIDATE / IMPORT
Canonical history (in-memory model or local JSON/SQLite cache)
   ↓  companion: PRESENT / GENERATE
Journey timeline + Story So Far recap
```

## Hard boundaries

- The addon stays dumb: OBSERVE, NORMALIZE, STORE. No AI, no APIs, no summaries,
  no analysis.
- The one exception is the read-only in-game journal (`addon/ChronicleUI.lua`,
  `/chronicle`). It may read `AzerothChronicleDB` and group, count and sort
  captured events for display. It must never write the SavedVariable, never
  add interpretation or AI, and never show anything not captured.
- The parser must **never** execute the SavedVariables file with a Lua runtime.
  Parse the restricted `AzerothChronicleDB = { ... }` syntax as data.
- A malformed or partially-written file must never destroy previously imported
  history — keep the last good state.
- Every event carries a stable id so re-importing the same file is idempotent.

## Schema (v1)

Account-level SavedVariable `AzerothChronicleDB`:

```lua
AzerothChronicleDB = {
    schemaVersion = 1,
    characters = {
        ["player-guid"] = {
            name, realm, race, class,
            events = { <ChronicleEvent>, ... }
        }
    }
}
```

Event types: `session_started`, `quest_accepted`, `quest_completed`,
`location_changed`. Event id: `<character-guid>:<type>:<questId|zone>:<timestamp>`.

Schema changes bump `schemaVersion`; the companion validates it and stays
backward-compatible.

## Story So Far

The only AI feature. Recap generation is abstracted behind a `StoryGenerator`
interface. Default provider: Amazon Bedrock (Nova). The recap must be grounded
in captured journey events — it never invents progression.
