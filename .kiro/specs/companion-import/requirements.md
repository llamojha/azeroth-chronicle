# Companion Import — Requirements

## Overview

The macOS companion (Tauri + Rust backend + web frontend) DISCOVERs, READs,
PARSEs, VALIDATEs, IMPORTs, PRESENTs, and GENERATEs. It treats
`AzerothChronicle.lua` as read-only, untrusted input and never modifies it.

## Requirements

### R1 — Directory selection & discovery
- **R1.1** The user SHALL select the WoW: Forever installation directory
  manually (no hardcoded path).
- **R1.2** After selection, the app SHALL validate that `WTF/`, an `Account/`
  folder, and a `SavedVariables/` folder exist, reporting each check.
- **R1.3** The app SHALL locate `AzerothChronicle.lua` under
  `WTF/Account/<ACCOUNT>/SavedVariables/`.
- **R1.4** The selected location SHALL be persisted locally across launches.

### R2 — Read-only, safe reads
- **R2.1** The app SHALL open the file read-only and NEVER write to it.
- **R2.2** The app SHALL handle a malformed or partially-written file WITHOUT
  destroying previously imported history (keep last good state).

### R3 — Parsing (no Lua runtime)
- **R3.1** The parser SHALL parse the restricted `AzerothChronicleDB = { ... }`
  syntax as DATA and SHALL NEVER execute the file with a Lua interpreter.
- **R3.2** The parser SHALL reject input that is not the expected shape.

### R4 — Validation
- **R4.1** The app SHALL validate `schemaVersion` and stay backward-compatible.
- **R4.2** The app SHALL validate character records and event records, dropping
  invalid events without failing the whole import. (An unknown event type never
  destroys valid existing events.)
- **R4.3** Missing optional quest metadata SHALL never cause import failure.

### R5 — Idempotent import & dedup
- **R5.1** Importing the same file N times SHALL yield exactly one stored copy of
  each event (dedup by event id).
- **R5.2** The import SHALL be additive: new events merge into existing history.

### R6 — Presentation
- **R6.1** Events SHALL display chronologically (stable ordering by timestamp,
  then id).
- **R6.2** The UI SHALL show character metadata (name, race, class, level).
- **R6.3** The UI SHALL show last synchronization/import state (e.g.
  "Last WoW sync: 18:42 · 12 new journey events imported"), NOT "Live".

### R7 — File watching (optional, safe)
- **R7.1** The app MAY watch the file; on change it SHALL wait for the write to
  settle, read a complete snapshot, and attempt parse.
- **R7.2** On parse success it imports; on failure it keeps previous state.

### R8 — Recap context assembly
- **R8.1** The app SHALL assemble a normalized `JourneyContext` (character
  metadata + recent relevant events + quest descriptions/objectives) for the
  recap generator.
- **R8.2** Recap generation SHALL be abstracted behind a `StoryGenerator`
  interface; the concrete provider (default: Amazon Bedrock Nova) SHALL be
  swappable.
- **R8.3** The recap SHALL be grounded in captured journey events and SHALL NOT
  invent arbitrary progression.

## Success conditions (measurable)

- User selects the Forever directory; the app finds and reads
  `AzerothChronicle.lua` without modifying it.
- Character and events parse; malformed/partial reads are handled safely.
- Repeated imports do not duplicate events.
- The timeline renders chronologically with last-sync state.
- Clicking "Story So Far" assembles context and returns a readable recap tied to
  the captured journey.
