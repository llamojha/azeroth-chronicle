# Companion Import — Tasks

Implementation-sized, independently testable. Maps to requirements (R#).
**Do not start significant work here until journey-capture proves end-to-end
(Day 1 objective).**

- [ ] **1. Tauri + React scaffold** — app builds and runs on macOS with an empty
  Journey shell. (Stack)
- [ ] **2. Directory selection** — native folder picker; store chosen path in
  local app data; reload on launch. (R1.1, R1.4)
- [ ] **3. Discovery + validation report** — verify `WTF/`, `Account/`,
  `SavedVariables/`; locate `AzerothChronicle.lua`; return per-check status to
  the UI. (R1.2, R1.3)
- [ ] **4. SavedVariables parser** — restricted data parser (NO Lua runtime);
  reject non-matching input; fixture tests incl. malformed input. (R3)
- [ ] **5. Model + validation** — typed Character/ChronicleEvent; drop invalid
  events individually; tolerate missing optional metadata. (R4)
- [ ] **6. Store + dedup + cache** — merge additively, dedup by id, JSON cache;
  bad parse leaves store untouched. (R2.2, R5)
- [ ] **7. `import` command** — wire read→parse→validate→store; return
  ImportResult (counts, last-sync). (R2–R6)
- [ ] **8. Timeline UI** — chronological render grouped by day, character header,
  last-sync status line (not "Live"). (R6)
- [ ] **9. `StoryGenerator` trait + Mock** — trait + deterministic offline impl;
  assemble JourneyContext; Story So Far button + recap panel. (R8.1, R8.2)
- [ ] **10. Bedrock Nova generator** — concrete provider grounded in events, no
  invented progression. (R8.2, R8.3)
- [ ] **11. File watcher (optional)** — debounce, keep-last-good on failure.
  (R7)
- [ ] **12. Property tests** — same-event N imports → 1 stored; timeline always
  ordered; malformed input never mutates prior history. (Success conditions)
- [ ] **13. Day-2 demo polish** — full flow: import → timeline → Story So Far;
  package the app. (Day 2 objective)
