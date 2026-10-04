# Companion Import — Tasks

Implementation-sized, independently testable. Maps to requirements (R#).
Journey-capture has passed its live acceptance gate; companion work is underway.

- [x] **1. Tauri + React scaffold** — app builds and runs on macOS with the
  field-journal shell. (Stack)
- [x] **2. Directory selection** — native folder picker (dialog plugin); chosen
  path stored in the app-data cache and prefilled on launch. (R1.1, R1.4)
- [x] **3. Discovery + validation report** — verify `WTF/`, `Account/`,
  `SavedVariables/`; locate `AzerothChronicle.lua`; per-check status surfaced in
  the UI status line. (R1.2, R1.3)
- [x] **4. SavedVariables parser** — restricted data parser (NO Lua runtime);
  reject non-matching input; fixture tests incl. malformed input. (R3)
- [x] **5. Model + validation** — typed Character/ChronicleEvent; drop invalid
  events individually; tolerate missing optional metadata. (R4)
- [x] **6. Store + dedup + cache** — merge additively, dedup by id, JSON cache;
  bad parse leaves store untouched. (R2.2, R5)
- [x] **7. `import` command** — Tauri `discover`/`import_journey`/`timeline`/
  `story_so_far` commands delegate to the `AppState` seam; import returns
  BatchResult (counts) and persists last-sync. (R2–R6)
- [x] **8. Timeline UI** — chronological render grouped by day, character header,
  last-sync status line (never "Live"). (R6)
- [x] **9. `StoryGenerator` trait + Mock** — trait + deterministic offline impl;
  assemble JourneyContext; Story So Far button + recap panel wired to the
  offline generator. (R8.1, R8.2)
- [ ] **10. Bedrock Nova generator** — provider implemented and offline-tested
  (grounding prompt, consent-gated), but NOT wired into the desktop command and
  NOT live-verified. The UI recap uses the offline generator; a consent toggle to
  the live provider is deferred. (R8.2, R8.3)
- [ ] **11. File watcher (optional)** — debounce, keep-last-good on failure.
  Deferred (optional polish). (R7)
- [x] **12. Property tests** — same-event N imports → 1 stored; timeline always
  ordered; malformed input never mutates prior history. (Success conditions)
- [x] **13. Day-2 demo polish** — full flow wired (import → timeline → Story So
  Far); `Azeroth Chronicle.app` bundled via `tauri build`. Pixel screenshots not
  captured in this environment (no display access). (Day 2 objective)

## Checkpoint — 2026-10-02

- The Rust core lives in `companion/src-tauri`. There is no Tauri binary or
  React implementation yet. Do not describe it as a packaged desktop app.
- Parser restrictions: one database assignment, table/literal data only,
  32 MiB input limit, bounded nesting, duplicate-key rejection, and no Lua VM.
- Validation supports schema 1. Invalid events are dropped individually;
  unsupported schemas and malformed tables leave history unchanged.
- Store imports are additive and deduplicate globally by event ID. Conflicting
  IDs preserve the original event and report a conflict. Cache writes use atomic
  replacement; a failed write does not publish the staged in-memory import.
- Discovery and import backend functions exist. Real read-only discovery passed
  four checks and found one save. Native folder selection and Tauri commands
  remain unimplemented, so tasks 2, 3, and 7 stay open.
- Real-save probe: 71 events added, zero invalid events or conflicts; importing
  again adds zero and reports 71 duplicates. One quest snapshot contains both
  description and objectives. No WoW file was written or executed.
- The offline StoryGenerator and recent-event context are implemented and tested.
  A real-save offline recap was generated. This is not cloud inference.
- The optional Bedrock provider compiles against the AWS Rust SDK, uses Converse,
  and requires per-request consent for data transfer and charges. Its prompt
  separates objectives from achievements and treats quest text as untrusted.
  No AWS request, account verification, or live Nova output has been tested.
  Prompt instructions alone are not proof of factual accuracy.
- A layout-agnostic command orchestration layer exists in `src-tauri/src/commands.rs`:
  `AppState` owns the imported `History` plus the companion app-data cache path and
  exposes `discover`, `import`, `timeline`, and `story_so_far`. These are the exact
  seams the Tauri `#[command]` handlers will delegate to; they are unit-tested but
  the Tauri binary and React UI are NOT built or launched, so task 7 stays open.
- Backend tests: 18 passing with the Bedrock feature (5 command-layer unit tests +
  13 import/context tests,
  including four proptest properties, plus two offline provider tests). Clippy
  passes with warnings denied, and cargo fmt --check passes. The session scratch path could not be
  canonicalized; approved fixture tests used ignored `target/test-tmp` instead.
  These tests do not establish Kiro IDE Correctness evidence.
- Three static mockups are in `companion/design-options.html`: A Field journal,
  B Campfire log, C Chapter book. A is recommended, but no choice is approved.
  Browser visual inspection failed: native browser tooling could not start its
  sandbox and the CLI browser target crashed. No screenshot proof is claimed.

## Build — 2026-10-03

- Layout A (Field journal) built: Tauri v2 (Rust) + React/Vite. Frontend in
  `companion/{src,index.html,vite.config.ts}`; desktop shell in
  `companion/src-tauri/src/{main.rs,desktop.rs}` behind the `desktop` feature so
  `cargo test` on the core never pulls Tauri. Native folder picker via
  `tauri-plugin-dialog`; ACL in `capabilities/default.json`.
- Verified: `cargo test --features bedrock` → 18 pass (5 command-layer + 13
  import/context incl. 4 proptests + 2 offline provider); `cargo fmt --check` and
  `cargo clippy --all-targets --features desktop,bedrock -D warnings` clean;
  `npm run build` (tsc + vite) clean. The debug AND release binaries launch and
  load the app-data cache without error (runtime proof of context/ACL/plugin
  wiring and `AppState::load`). `tauri build -f desktop` produced
  `src-tauri/target/release/bundle/macos/Azeroth Chronicle.app` (~9 MiB).
- NOT verified here: pixel screenshots of the rendered window — this environment
  has no display access (`screencapture` and the CLI browser both fail). Visual
  fidelity to the mockup rests on the ported tokens/structure, not a captured
  image. Run `cd companion && npm run tauri dev` (or open the bundled `.app`) to
  see it, then import the real 71-event save.
- Live Bedrock Nova is NOT wired into the desktop recap and NOT called; the UI
  uses the offline generator only. No AWS request made; no charges.

## Next steps and approval boundaries

1. ✅ Layout **A (Field journal)** selected on 2026-10-03 — timeline + recap side
   by side, import status always visible. The mockup in `companion/design-options.html`
   is the visual spec.
2. Add the Tauri/React shell, folder picker, app-data ownership, commands, import
   status, recap controls, and failure states. Run filesystem/recap work off the
   UI thread. StoryGenerator is currently synchronous; use a blocking worker.
3. Verify the rendered app, first-run usability, and native build/package.
4. Ask for explicit consent before any live Nova request. Verify configured
   account, region, and model availability without reading credential files.
5. Add the optional watcher after manual import is verified, or record it as
   deliberately deferred rather than completed.

No commits, pushes, PRs, visibility changes, or cloud resources were created.
