# Journey Capture — Tasks

Implementation-sized, independently testable. Each maps to requirements (R#).

- [x] **1. `.toc` manifest** — declare Interface, Title, Notes,
  `## SavedVariables: AzerothChronicleDB`, and the Lua file. (R6.1)
- [x] **2. DB bootstrap** — on load, ensure `AzerothChronicleDB` with
  `schemaVersion=1` and `characters={}`. Idempotent init. (R6.1, R6.3, R8)
- [x] **3. Character identity + get-or-create** — resolve name/realm/race/class/
  level/guid; create the character record on first sight; update level without
  clearing events. (R1.1–R1.3)
- [x] **4. Event dispatch skeleton** — frame, `RegisterEvent`, `OnEvent` switch;
  loads with no Lua errors on `PLAYER_LOGIN`. (R7)
- [x] **5. Normalizer** — `MakeEventId`, `MakeEvent(type, fields)`, `Location()`
  helper; pure where possible. (R5.1, R2)
- [x] **6. Store with dedup** — `AppendEvent` skips an id already present. (R5.2)
- [x] **7. `session_started`** — record on login with level. (R2.1)
- [x] **8. Location capture** — meaningful transitions only, no coord polling,
  no consecutive duplicates. (R2.4, R4.1, R4.2)
- [x] **9. Quest accept + resolver** — remember questId, resolve now or on
  `QUEST_LOG_UPDATE`, persist snapshot; tolerate missing metadata. (R2.2, R3)
- [x] **10. Quest completion** — capture on turn-in with zone/subzone. (R2.3)
- [x] **11. Normalization tests** — fixture-based tests for id construction,
  snapshot assembly, dedup, and missing-metadata tolerance, runnable without the
  client. (Success conditions)
- [x] **12. Day-1 live proof** — play, accept + complete a real quest, change
  zones, `/reload`, inspect `AzerothChronicle.lua`, confirm valid structured
  history and no duplicates. (Day 1 objective)

## Verified closeout — 2026-10-02

The verified live save contains 71 events: 5 sessions, 42 location transitions,
13 quest acceptances, and 11 completions. There are zero duplicate event IDs.
Quest 92516, "Hippogryph Harassment", includes a title, description, objectives,
timestamp, and location, followed by completion. This satisfies tasks 9 and 12.
Older events with missing quest text remain unchanged.

The last automated addon run had 35 passing tests, plus successful Lua syntax
and git whitespace checks. This documentation closeout did not rerun those tests.
The in-game GetBuildInfo screenshot confirms Forever 1.60.1, build 70170,
Interface 16001. The manifest uses 16001.

## Implementation details and limits

- Database guards, real GUID identity, session capture, and meaningful location
  transitions preserve existing valid history.
- All four event types use MakeEvent. Collision suffixes retain distinct
  same-second occurrences; direct store tests verify duplicate IDs are rejected.
- The quest reader checks the returned quest ID, reads text from the selected
  log entry, and restores selection even if text retrieval throws. Nested log
  updates are suppressed during selection.
- Incomplete metadata gets one retry on QUEST_LOG_UPDATE, then a partial
  immutable snapshot. Logout, removal, and turn-in flush pending acceptance.
  Acceptance time and location describe the original occurrence.
- Removal permits reacceptance without inventing a completion. Duplicate
  turn-ins are suppressed until fresh acceptance in the current addon load.
  Cross-reload notification replay suppression is not proven.
- QUEST_DETAIL caches one quest-ID-matched offer using GetQuestID, GetTitleText,
  GetQuestText, and GetObjectiveText. Viewing alone creates no event; acceptance
  copies the snapshot and consumes the offer cache. This path is live-verified.
- Lua 5.1 execution, every API fallback, and other client builds remain unverified.
  The local Lua 5.5/luacheck incompatibility remains; lint is not claimed.

## API evidence

- [Classic quest event/API definitions](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua)
- [Vanilla quest-log UI](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_UIPanels_Game/Vanilla/QuestLogFrame.lua)
- [Beta quest-dialog UI](https://github.com/Gethe/wow-ui-source/blob/classic_beta/Interface/AddOns/Blizzard_UIPanels_Game/Vanilla/QuestInfo.lua)

The adapter accepts both two-argument and single-ID acceptance shapes. Late text
arriving after the bounded retry is not added to immutable history. Source
references guide implementation; the live save supplies client acceptance proof.

Next: companion-import. No additional gameplay is needed to close this spec.
