# Companion Import — Design

## Stack

- **Shell:** Tauri (Rust backend, web frontend). macOS-native packaging, local
  filesystem access, small runtime.
- **Frontend:** React + Vite (fastest Tauri path). Single Journey screen +
  Story So Far panel. No dashboards, no router unless needed.
- **Persistence (MVP):** in-memory model backed by a small local JSON cache in
  the app's data dir. SQLite is a later upgrade, not required for the 2-day MVP.

## Backend architecture (Rust, `src-tauri`)

```
commands (Tauri #[command])
   ├─ select_wow_dir(path) -> ValidationReport      (R1.2)
   ├─ discover_db() -> Option<PathBuf>               (R1.3)
   ├─ import() -> ImportResult                       (R2–R5)
   ├─ get_timeline() -> TimelineView                 (R6)
   ├─ start_watch() / stop_watch()                   (R7)
   └─ story_so_far() -> Recap                        (R8)

modules
   ├─ discovery   : validate WTF/Account/SavedVariables, find the .lua
   ├─ savedvars   : restricted parser (NO Lua runtime)   (R3)
   ├─ model       : Character, ChronicleEvent, JourneyContext
   ├─ store       : merge + dedup by id, JSON cache      (R5)
   ├─ watcher     : notify + debounce, keep-last-good     (R7)
   └─ story       : StoryGenerator trait + Bedrock Nova impl (R8)
```

## SavedVariables parser (the critical safety piece)

- Input is a restricted subset: `AzerothChronicleDB = { ... }` containing nested
  tables, string/number/boolean literals, and `["key"] = value` / positional
  entries. NO functions, NO metatables.
- Implement a small hand-rolled tokenizer + recursive-descent parser (or a
  vetted Lua-table-as-data crate) that consumes ONLY data. It must:
  - never `eval` / run a Lua VM (R3.1),
  - reject unexpected constructs (R3.2),
  - return a typed `RawDb` for validation.
- Validation layer maps `RawDb` -> typed model, dropping invalid events
  individually (R4.2) and tolerating missing optional fields (R4.3).

## Import & dedup

```
parse -> validate -> for each event: if id not in store, insert
```
Idempotent by construction (R5.1). Import is additive; a bad parse aborts the
import and leaves the previous store untouched (R2.2).

## File watching

`notify` crate → debounce (e.g. 500 ms after last write) → read full snapshot →
parse. Success imports; failure logs and keeps last good state (R7.2).

## Story So Far

```rust
pub struct JourneyContext { character: Character, events: Vec<ChronicleEvent> }

pub trait StoryGenerator {
    fn generate_story_so_far(&self, ctx: &JourneyContext) -> Result<String, String>;
}
```

The current trait is synchronous. Tauri commands must call providers on a
blocking worker, never the UI thread or inside an existing async runtime.
The offline implementation is the default until the user explicitly consents
to sending journey data to AWS and incurring model charges.

- Cloud impl: `BedrockNovaGenerator` — calls Amazon Bedrock (Nova) via the AWS
  SDK, with a prompt that: (a) lists character + ordered events + quest text,
  (b) instructs the model to summarize ONLY what happened, name people/threads
  that appear in the events, and NOT invent progression (R8.3).
- The trait boundary lets a `MockGenerator` (deterministic, offline) back tests
  and demos without cloud calls.

## Frontend (React)

Single screen mirroring the brief's mock: character header, chronological
timeline grouped by day, a `[ Story So Far ]` button that calls `story_so_far`
and renders the recap. A small status line shows last-sync state (R6.3).

## Failure modes & mitigations

| Failure | Mitigation |
|---|---|
| Wrong directory chosen | validation report per folder (R1.2) |
| Partial/malformed file | abort import, keep last good state (R2.2, R7.2) |
| Unknown/invalid event | drop that event, keep the rest (R4.2) |
| Repeated import | dedup by id (R5.1) |
| Bedrock unavailable | surface error; MockGenerator for offline/demo |

## Implementation phases

1. Tauri scaffold + React shell that runs on macOS.
2. Directory select + discovery + validation report + persisted path.
3. SavedVariables parser + model + validation (with fixtures).
4. Store + dedup + JSON cache; `import` command.
5. Timeline UI + last-sync state.
6. `StoryGenerator` trait + Mock impl + Story So Far UI.
7. Bedrock Nova impl.
8. File watcher (optional polish).
