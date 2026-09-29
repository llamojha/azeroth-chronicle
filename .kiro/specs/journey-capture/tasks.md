# Journey Capture — Tasks

Implementation-sized, independently testable. Each maps to requirements (R#).

- [ ] **1. `.toc` manifest** — declare Interface, Title, Notes,
  `## SavedVariables: AzerothChronicleDB`, and the Lua file. (R6.1)
- [ ] **2. DB bootstrap** — on load, ensure `AzerothChronicleDB` with
  `schemaVersion=1` and `characters={}`. Idempotent init. (R6.1, R6.3, R8)
- [ ] **3. Character identity + get-or-create** — resolve name/realm/race/class/
  level/guid; create the character record on first sight; update level without
  clearing events. (R1.1–R1.3)
- [ ] **4. Event dispatch skeleton** — frame, `RegisterEvent`, `OnEvent` switch;
  loads with no Lua errors on `PLAYER_LOGIN`. (R7)
- [ ] **5. Normalizer** — `MakeEventId`, `MakeEvent(type, fields)`, `Location()`
  helper; pure where possible. (R5.1, R2)
- [ ] **6. Store with dedup** — `AppendEvent` skips an id already present. (R5.2)
- [ ] **7. `session_started`** — record on login with level. (R2.1)
- [ ] **8. Location capture** — meaningful transitions only, no coord polling,
  no consecutive duplicates. (R2.4, R4.1, R4.2)
- [ ] **9. Quest accept + resolver** — remember questId, resolve now or on
  `QUEST_LOG_UPDATE`, persist snapshot; tolerate missing metadata. (R2.2, R3)
- [ ] **10. Quest completion** — capture on turn-in with zone/subzone. (R2.3)
- [ ] **11. Normalization tests** — fixture-based tests for id construction,
  snapshot assembly, dedup, and missing-metadata tolerance, runnable without the
  client. (Success conditions)
- [ ] **12. Day-1 live proof** — play, accept + complete a real quest, change
  zones, `/reload`, inspect `AzerothChronicle.lua`, confirm valid structured
  history and no duplicates. (Day 1 objective)
