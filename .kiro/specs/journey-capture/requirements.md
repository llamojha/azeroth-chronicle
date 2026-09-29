# Journey Capture — Requirements

## Overview

The Azeroth Chronicle addon records a character's personal journey as structured,
immutable events inside an account-level SavedVariable (`AzerothChronicleDB`),
which WoW: Forever flushes to `AzerothChronicle.lua`. This spec covers the addon
side only: OBSERVE, NORMALIZE, STORE.

## Requirements

### R1 — Character identity
- **R1.1** On login, the addon SHALL identify the current character: name, realm,
  race, class, level, and a stable GUID.
- **R1.2** The addon SHALL key each character by GUID inside
  `AzerothChronicleDB.characters`, creating the record on first sight.
- **R1.3** Character records SHALL update mutable metadata (e.g. level) without
  destroying that character's `events`.

### R2 — Supported event types
The addon SHALL capture only these event types:
- **R2.1** `session_started` (optional but recorded on login): timestamp,
  characterId, level.
- **R2.2** `quest_accepted`: questId, title, description, objectivesText, zone,
  subzone, mapId, timestamp.
- **R2.3** `quest_completed`: questId, zone, subzone, timestamp.
- **R2.4** `location_changed`: zone, subzone, mapId, timestamp.

### R3 — Quest snapshot behavior
- **R3.1** On `QUEST_ACCEPTED`, the addon SHALL remember the questId and attempt
  to resolve title/description/objectives immediately.
- **R3.2** If metadata is incomplete, the addon SHALL defer resolution until
  `QUEST_LOG_UPDATE` and resolve the snapshot then.
- **R3.3** The addon SHALL persist the text captured at play time (a snapshot),
  not a reference to be fetched later.
- **R3.4** A quest with unresolved metadata SHALL still produce a valid event
  (missing optional fields are acceptable).

### R4 — Location transition behavior
- **R4.1** The addon SHALL record a `location_changed` event only on a MEANINGFUL
  transition (zone or subzone actually changed).
- **R4.2** The addon SHALL NOT capture continuous coordinates or emit duplicate
  consecutive identical locations.

### R5 — Event identity & idempotency
- **R5.1** Every event SHALL carry a stable id:
  `<guid>:<type>:<questId|zone>:<timestamp>` (or a generated UUID fallback).
- **R5.2** The addon SHALL NOT write two events with the same id.
- **R5.3** Re-importing the same SavedVariables file SHALL be idempotent on the
  companion side (guaranteed by stable ids).

### R6 — Persistence
- **R6.1** All persistence SHALL be via the account-level SavedVariable
  `AzerothChronicleDB` (declared in the `.toc`), never per-character files.
- **R6.2** Captured events SHALL be immutable once written.
- **R6.3** `AzerothChronicleDB.schemaVersion` SHALL be `1` for this spec.

### R7 — Error handling & sandbox discipline
- **R7.1** Missing or nil optional fields SHALL never error.
- **R7.2** The addon SHALL NOT perform network calls, AI, summaries, or analysis.
- **R7.3** The addon SHALL NOT claim realtime synchronization anywhere.

### R8 — Backward-compatible schema versioning
- **R8.1** Any future schema change SHALL bump `schemaVersion`.
- **R8.2** The on-disk shape SHALL remain parseable as data (no function values,
  no metatables required to read it).

## Success conditions (measurable)

- Playing WoW, accepting a real quest, completing it, and changing zones, then
  `/reload`, yields a well-formed `AzerothChronicle.lua` containing the
  corresponding events with populated fields and stable ids.
- No duplicate events are produced during normal play.
- Normalization logic passes fixture-based tests independent of the live client.
