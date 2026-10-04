# Azeroth Chronicle: project and Kiro University guide

A personal memory for your World of Warcraft character. A Lua addon records the journey; a macOS companion turns it into a chronological journal and an offline recap. Kiro agents reuse the imported history for reports, stories, lore reviews, and social drafts.

Status: October 3, 2026. This guide reflects the completed local MVP and the user's successful Power test. Older READMEs and historical spec checkpoints still contain pre-implementation statuses and need reconciliation.

## What the project does

The flow is **Play → Capture → Save → Import → Journal → Story So Far**.

- Captures sessions, accepted and completed quests, available quest text, locations, and timestamps.
- Imports SavedVariables as restricted data without executing Lua or changing game files.
- Keeps persistent local history, deduplicates events, and preserves good history after malformed reads.
- Presents a Tauri/Rust/React field journal with manual import and an offline recap.
- Provides specialized Kiro agents and a reusable WoW addon development Power.

Both product specs have reached the working local MVP. Live Bedrock integration and the optional file watcher remain explicitly deferred in the companion checklist. The desktop recap uses a deterministic offline generator, not Nova.

## Install and use

### Addon

Create an AzerothChronicle folder inside your WoW client's Interface/AddOns directory. Copy both files from [addon](addon/) into it. Restart WoW and enable Azeroth Chronicle at character selection.

The verified client is WoW: Forever 1.60.1, build 70170, Interface 16001. Other builds require compatibility checks, not just a manifest-number change.

Play normally: accept quests, complete them, and move between zones or subzones. WoW writes SavedVariables on /reload, logout, or normal exit. Events remain in memory until that write; a crash can lose newer events. Missing historical quest text is not invented or backfilled.

### Companion

Open the macOS companion, select the WoW client folder, and import its saved history. Browse the timeline and select Story So Far. Import again after a later game save; repeated imports do not duplicate events.

Import is manual. There is no live game connection or enabled watcher.

For development, install Node.js/npm, Rust/Cargo, and the native macOS build tools required by Tauri. From the repository root:

```sh
cd companion
npm install
npm run tauri -- dev --features desktop
```

The desktop feature is required by the Rust binary; the option was checked against the installed Tauri CLI. The previously built app is under companion/src-tauri/target/release/bundle/macos/. It is a local artifact, not a published, signed, or notarized release.

## Architecture and safety

| Component | Responsibility |
| --- | --- |
| [Addon](addon/) | Observe client events, normalize them, store stable IDs and quest snapshots. |
| [Rust backend](companion/src-tauri/src/) | Discover saves, parse literal data, validate events, merge history, persist cache, prepare recap context. |
| [React frontend](companion/src/) | Folder selection, import feedback, timeline, and recap display. |
| [Kiro configuration](.kiro/) | Specs, steering, hooks, agents, MCP servers, and Power. |

SavedVariables is an ingestion boundary, not the companion database. The companion never executes the save as Lua. Unsupported schemas and malformed files preserve existing history. Conflicting duplicate IDs retain the original event and report the conflict. Cache writes belong to the companion, not the game directory.

The optional Bedrock provider requires consent for data transfer and charges, but is not connected to the desktop recap. No AWS credentials belong in this repository.

Accounts, cloud synchronization, Windows/Linux distributions, live gameplay control, and a runtime lore database are outside the MVP.

## The seven Kiro University lessons

Configuration, actual use, and retained evidence are separate. These statuses describe project evidence, not an awarded challenge result. The older [lesson map](KIRO_LESSONS.md) contains more detail but has stale status entries.

| Lesson | How we applied it | Status and remaining evidence |
| --- | --- | --- |
| 1. Spec-driven development | [Journey capture](.kiro/specs/journey-capture/) and [companion import](.kiro/specs/companion-import/) define requirements, design, and implementation tasks. | Working local flow delivered. Live Nova and watcher remain deferred. |
| 2. Steering | [Steering files](.kiro/steering/) preserve product scope, architecture, read-only game-file rules, and build-sensitive addon guidance. | Applied project context recorded. |
| 3. Hooks | [Test-on-save](.kiro/hooks/test-on-save.json) invokes addon and available Rust tests when relevant source changes. | Configured. Retain an actual Kiro-triggered execution and result; a manual run is different evidence. |
| 4. Property-based testing / Correctness | [Rust tests](companion/src-tauri/tests/) cover parser safety, repeated imports, ordering, and history preservation; [Lua tests](addon/tests/) cover addon behavior. | Properties implemented. Kiro IDE Correctness workflow/artifact still pending. |
| 5. MCP | [MCP configuration](.kiro/settings/mcp.json) includes WoW API and AWS servers. [Lore review](companion/examples/lore-review-2026-10-03.md) records actual WoW calls and findings. | WoW use verified through a stdio client. Retain Kiro-native calls; authenticated AWS use is not claimed. |
| 6. Custom agents | [Five agents](.kiro/agents/) specialize in addon implementation, factual journals, storytelling, lore, and social drafts. [Examples](companion/examples/) record outputs. | Usage recorded against imported history. Generated content still needs grounding review. |
| 7. Powers | [WoW addon development](.kiro/powers/wow-addon-development/) bundles instructions and WoW MCP tools. | User confirmed it works in Kiro on October 3. Retain activation/task evidence; bundled MCP calls were not separately confirmed. |

### What MCP contributed

The WoW MCP review resolved Interface 16001 to Forever and searched wiki references for Zephras Isle and the Skyborne. Its dataset build was older than the verified client, so API results were treated as research rather than live compatibility proof.

The review found that public lore exists, contrary to the example's premise. It also corrected coverage to 45 of 56 unique quests with descriptions, identified altered quotations, and flagged suspicions presented as facts. The Turncoat has no captured completion and must stay unfinished.

These findings are recorded in the [review](companion/examples/lore-review-2026-10-03.md). Corrections to the example and loremaster guidance remain pending. External references checked the premise; they did not fill gaps in player history.

AWS MCP is configured for documentation and authorized cloud work. Launcher validation does not establish authentication or a live Nova call.

### Extra journey-content work

The agents are wow-addon-developer, journey-journalist, adventure-herald, journey-storyteller, and journey-loremaster. They separate implementation from factual reporting, creative retelling, lore synthesis, and social drafting.

The later imported journey contains 244 events. The [story](companion/examples/story-willpala.md) and [lore report](companion/examples/lore-willpala.md) demonstrate reuse of that history. Read the lore report alongside its review, not as a fully validated source. Social drafts were also prepared from recorded events.

These are development-time Kiro workflows, not features automatically called by the desktop recap button.

## Optional bonuses

### Bonus 2: Package a Power

The [package](.kiro/powers/wow-addon-development/README.md) contains a manifest, WoW MCP pinned to version 0.2.0, and a self-contained quest-capture/lore-review skill.

- [x] Author the package and installation instructions.
- [x] Validate JSON syntax and expected files.
- [x] Receive user confirmation that it works in Kiro.
- [ ] Retain activation and real-task results as submission evidence.
- [ ] Include the tested package in the submitted repository.

Lesson 7 demonstrates using a Power; this bonus demonstrates creating and packaging one. Curated-registry publication is optional. See [Kiro's Power format and local testing instructions](https://kiro.dev/docs/powers/create/).

### Bonus 1: Kiro Web, cloud sessions, and cloud configuration

Planned, not completed. The proposed task is a bounded addon review against the spec, with relevant Lua checks in a cloud session. Live WoW validation remains local.

- [ ] Confirm eligible paid-plan access.
- [ ] Make the intended project revision available to the cloud session.
- [ ] Sync supported configuration and check what actually loads.
- [ ] Run the review and checks; retain session and configuration evidence.
- [ ] Demonstrate continuity across supported Kiro surfaces if available.
- [ ] Review useful changes before integrating them.

Both bonuses are optional, worth 250 credits each under the [challenge terms](https://kiro.dev/2026/university/terms/). Neither is required for the seven-lesson completion award.

## Validation record

Previously recorded results, not tests rerun for this documentation update:

- Addon: 35 tests passed; live capture verified text, turn-ins, location changes, timestamps, and persistence.
- Initial live proof: 71 events, zero duplicate IDs, including Hippogryph Harassment with text and completion.
- Import proof: re-importing the 71-event save added zero events.
- Companion: 18 backend tests with the Bedrock feature; formatting, Clippy, and frontend build checks passed in the recorded build.
- A macOS app bundle was produced; later imported history reached 244 events.
- Power: user-reported success in Kiro, October 3, 2026.

Offline addon tests initially missed a real quest-text compatibility bug. Capturing offer-window text fixed it; a subsequent gameplay save verified it. Mocked tests and live evidence therefore remain separate.

Earlier desktop screenshot checks were blocked by the environment. A package build is not visual proof. The local Lua 5.5 toolchain also had a luacheck incompatibility; skipped lint is not passing lint.

## Remaining work and submission

Engineering and evidence:

- [ ] Capture the Kiro hook firing and its result.
- [ ] Complete and retain Kiro IDE Correctness evidence.
- [ ] Save the working Power session and any bundled MCP calls.
- [ ] Apply lore-review corrections to the example and agent guidance.
- [ ] Reconcile older READMEs, lesson statuses, and historical spec checkpoints.
- [ ] Decide whether to pursue the optional cloud bonus.
- [ ] Keep Nova integration and the watcher deferred unless implemented and verified.

Final submission, following the [official terms](https://kiro.dev/2026/university/terms/):

- [ ] Verify eligibility, account age, and commit dates.
- [ ] Publish the intended files in the participant's public repository, including .kiro/.
- [ ] Record a public 30-second to 3-minute working demo covering the lessons.
- [ ] Post on X or LinkedIn with repository, video, short description, #KiroUniversity, #BuildWithKiro, and the relevant Kiro tag.
- [ ] Submit links and the lesson writeup through the [challenge page](https://kiro.dev/2026/university/).
- [ ] Freeze commits after the deadline until judging ends or the award email arrives, whichever is earlier.

Deadline: October 6, 2026 at 06:59 UTC (08:59 Europe/Madrid). The judging freeze ends no later than October 20 at 06:59 UTC, subject to the earlier-award-email condition. Repository visibility and submission completion were not reverified for this update.
