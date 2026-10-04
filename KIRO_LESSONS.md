# Kiro University Challenge — Lesson Evidence

This document maps each of the **7 Kiro University lessons** to where its
evidence lives in this repository and what was done. It is the guide judges (and
future-me) can follow to see how each capability was applied to **Azeroth
Chronicle**.

> Challenge window: 2026-09-21 → final submission 2026-10-06 06:59 UTC.
> One project, seven lessons applied progressively.

## Status legend

- ✅ **Done** — the described work has evidence; this does not imply it is committed.
- Configuration alone does not prove activation or a completed challenge lesson.
- 🟡 **Partial** — scaffolded here; a step must still be completed (often in the
  Kiro IDE / against the live client).
- 🔴 **Todo** — not yet done.

---

## Summary

| # | Lesson | Evidence path | Status |
|---|--------|---------------|--------|
| 1 | Spec-Driven Development | `.kiro/specs/` | ✅ Done |
| 2 | Steering | `.kiro/steering/` | ✅ Done |
| 3 | Hooks | `.kiro/hooks/test-on-save.json` | ✅ Done |
| 4 | Property-based Testing (Correctness) | `addon/tests/` + `companion/src-tauri/tests/` + CI | ✅ Done |
| 5 | MCP | `.kiro/settings/mcp.json` | ✅ Done |
| 6 | Custom Agents | `.kiro/agents/` (5 agents, used — outputs in `companion/examples/`) | ✅ Done |
| 7 | Powers | `.kiro/powers/wow-addon-development/` | ✅ Done |
| Bonus 2 | Package a Kiro Power | `.kiro/powers/wow-addon-development/` (`plugin.json`, `README.md`, `mcp.json`, `skills/`) | ✅ Done |
| Bonus 1 | Kiro Web / cloud sessions | — | 🔴 Not done |

---

## Lesson 1 — Spec-Driven Development ✅

**Where:** `.kiro/specs/journey-capture/` and `.kiro/specs/companion-import/`,
each with `requirements.md`, `design.md`, `tasks.md`.

**What was done:** The two core features of the product are defined as specs
before implementation. `journey-capture` (the WoW addon) defines supported event
types, the SavedVariables format, quest-snapshot behavior, event identity,
error handling, and schema versioning (R1–R8), with a design pipeline
(WoW events → adapters → normalized `ChronicleEvent` → `AzerothChronicleDB`) and
implementation-sized tasks. `companion-import` does the same for the macOS
companion (discover → read → parse → validate → import → present → generate).

**Continuity:** These requirements feed Lesson 4 — their invariants become the
properties under test.

---

## Lesson 2 — Steering ✅

**Where:** `.kiro/steering/product.md`, `architecture.md`,
`wow-addon-development.md`.

**What was done:** Persistent project context lives in steering rather than being
re-explained each session:
- `product.md` (always-on) — product purpose, the one flow
  `Play → Capture → Import → Journal → Recap`, positioning, out-of-scope list.
- `architecture.md` (always-on) — hard boundaries: SavedVariables as an ingestion
  boundary not the DB, companion never writes to WoW files, idempotent imports,
  events over mutable state, the v1 schema.
- `wow-addon-development.md` (`fileMatch` on `addon/**` and the journey-capture
  spec) — the WoW addon sandbox rules, `.toc` essentials, event lifecycle, quest
  snapshot strategy, API discipline.

**Note for Lesson 6:** Steering files are **not** auto-loaded into a Custom
Agent — the `wow-addon-developer` agent lists the relevant steering files
explicitly in its `resources` (see Lesson 6).

---

## Lesson 3 — Hooks ✅

**Where:** `.kiro/hooks/test-on-save.json`.

**What was done:** A `fileEdited` hook that runs the real test suite when addon
or companion source changes (patterns: `addon/**/*.lua`,
`companion/src-tauri/src/**/*.rs`, `companion/src/**/*.{ts,tsx}`). It invokes the
addon runner (`addon/tests/run.sh` → `luac` syntax check + `busted`) and the Rust
suite when the companion exists. This supports the actual dev flow (per the
article's guidance: hooks must support real development, not exist to demo hooks).

---

## Lesson 4 — Property-based Testing (Correctness) ✅

**Where:** `addon/tests/` (Lua harness) and `companion/src-tauri/tests/import.rs`
(Rust `proptest`), both run in CI (`.github/workflows/ci.yml`).

**What was done:** The companion's correctness invariants — taken straight from
the specs' success conditions — are enforced as property tests that generate many
randomized inputs and shrink any failure to a minimal counterexample:
- `arbitrary_input_does_not_panic` — the restricted parser never panics on any
  byte string (safety).
- `n_imports_are_idempotent` — importing the same save N times yields exactly one
  stored copy (dedup).
- `timeline_is_ordered_and_stable` — the timeline is always sorted by
  `(timestamp, id)`.
- malformed input never mutates prior history (keep-last-good).

The backend suite passes **18 tests** with the Bedrock feature (5 command-layer +
13 import/context, including the 4 properties above + 2 offline provider tests);
Clippy (`-D warnings`) and `cargo fmt --check` are clean. The Lua addon harness
(`wow_stubs.lua` fakes the client APIs offline; `run.sh` runs `luac -p` +
`busted`) adds **35 passing specs**. CI runs all of it on every push/PR (the
`core` and `addon` jobs).

Kiro's *Correctness* feature is **Kiro IDE-only**; the `proptest`/`busted`
properties here are complementary engineering evidence alongside it.

**Toolchain caveat:** the local runtime is Homebrew **Lua 5.5.1**; `luacheck`
does not run on 5.5 (skipped, non-fatal). WoW addons target Lua 5.1 semantics —
harness is fine for logic tests but is not a faithful 5.1 runtime.

---

## Lesson 5 — MCP ✅

**Where:** `.kiro/settings/mcp.json` (project-scoped configuration).

**What was done:** Configured two enabled MCP servers:

- `wow-api`: launches `@nighthawk42/wow-api-mcp` through `npx`, with
  `WOW_API_MCP_FLAVOR=forever`. Intended use: research quest APIs and event
  payloads, then verify the addon interface version against the actual client.
- `aws-mcp`: launches `mcp-proxy-for-aws@latest` through `uvx`, using the
  official managed AWS MCP endpoint and region metadata for `us-east-1`.
  Intended use: AWS documentation and IAM-authorized API access while developing
  the Bedrock Nova recap integration.

Both configurations have empty `autoApprove` lists. No AWS credentials are
stored in the project configuration; authentication uses the developer's AWS
credential chain. The companion will call Bedrock through the AWS SDK behind
`StoryGenerator`; MCP supports the development workflow.

**Validation completed during setup:** JSON validation passed; npm reported
WoW API MCP version `0.2.0` and its launcher reported `serving on stdio`;
AWS proxy `--help` succeeded and reported version `1.7.0`. These are observed
versions, not pinned dependencies.

**Sources:** [WoW API MCP](https://github.com/Nighthawk42/wow_api_mcp) and
[AWS MCP setup](https://awslabs.github.io/mcp/installation).

---

## Lesson 6 — Custom Agents ✅

**Where:** `.kiro/agents/` — `wow-addon-developer.json` plus four journey-content
agents: `journey-journalist.json`, `adventure-herald.json`,
`journey-storyteller.json`, `journey-loremaster.json`.

**What was done:** Five specialized agents, each with a focused tool set, a prompt
enforcing its scope, and `resources` that **explicitly** load the steering/spec
files it needs (steering is not auto-injected into a Custom Agent):
- `wow-addon-developer` — addon-side Lua only; WoW sandbox + schema discipline,
  "never invent unavailable WoW APIs."
- `journey-journalist` — imported save → Markdown adventure report.
- `adventure-herald` — latest adventure → short social post.
- `journey-storyteller` — narrative retelling, chapters by day.
- `journey-loremaster` — the island's story synthesized from captured quest text.

**Usage evidence:** the four content agents were run against the real 244-event
save; their grounded outputs are committed under `companion/examples/`
(`story-willpala.md`, `lore-willpala.md`, with a README). Every one enforces the
project's grounding rule — captured events only, no invented lore, an
accepted-but-unfinished quest never shown as done.

---

## Lesson 7 — Powers ✅

**Where:** `.kiro/powers/wow-addon-development/POWER.md`.

The Power was activated and used inside Kiro (2026-10-03).

**What was done:** A reusable Power capturing WoW addon knowledge: `.toc`
structure, SavedVariables mechanics, the event lifecycle, quest APIs (with the
"verify per build" discipline), event-driven Lua patterns, sandbox limitations,
and Forever compatibility notes. It backs the `wow-addon-developer` agent and the
journey-capture work — an extension of capabilities already added, per the
article's framing of Powers as dynamically-loaded specialized knowledge.

---

## Optional bonuses

Each is worth 250 additional credits; neither is required for the 1,000-credit
completion reward.

### Bonus 2 — Package a Kiro Power (250 credits) ✅

- [x] Check the current official Power packaging requirements.
- [x] Extend the existing `.kiro/powers/wow-addon-development/` scaffold into
  a reusable WoW Forever Addon Development Power: SavedVariables guidance,
  quest-event research, client-version verification, WoW API MCP configuration,
  and an addon-validation workflow.
- [x] Document installation, prerequisites, supported client versions, and use.
- [x] Test installation and activation in Kiro.
- [x] Apply the Power to a real journey-capture task and retain the result as
  evidence. Lesson 7 demonstrates use; this bonus demonstrates packaging.
- [x] Include the Power package and evidence in the final submission.
  Submission to the curated registry is optional.

### Bonus 1 — Kiro Web, cloud sessions and cloud configuration (250 credits) 🔴 Not done

- [ ] Confirm access through an eligible Pro, Pro+, Pro Max, or Power subscription
  and the US East (N. Virginia) service region.
- [ ] Open the project in Kiro Web and configure supported project context
  through cloud configuration; verify which steering, hooks, skills, Powers,
  and custom-agent settings are actually available in the cloud session.
- [ ] Demonstrate continuing a cloud session from the CLI or IDE.
- [ ] Run a bounded addon review against the journey-capture spec and execute
  the relevant Lua checks in the cloud; use the packaged Power if supported.
- [ ] Review and integrate useful fixes, recording the actual checks and results.
- [ ] Retain session evidence, configuration evidence, and resulting changes
  for the final submission. Live WoW gameplay validation remains a local step.

---

## Submission checklist (from the article's rules)

- [ ] Repo is **public** (currently private — flip before submission).
- [x] Repo on the participant's GitHub account.
- [x] No commits before 2026-09-21 16:00 UTC (first commit is 2026-09-29).
- [x] `.kiro/` directory present with lesson evidence.
- [ ] Project is functional (end-to-end `Play → … → Story So Far` proven).
- [ ] Public video 30s–3min showing the project + each lesson.
- [ ] Social post (X or LinkedIn) with repo, 2–3 sentence description, video,
      `#KiroUniversity`, `#BuildWithKiro`, and the Kiro tag.
- [ ] Final form submitted (repo, video, social post, per-lesson explanation).
- [ ] After the deadline, no new commits until judging ends (2026-10-20 06:59 UTC).

**Open gaps to close:** make the repo public; the functional end-to-end proof
(needs the WoW: Forever client) and the video.

## Spec implementation evidence — 2026-10-02

Spec 1 is closed: the verified live save has 71 events, zero duplicate IDs,
and quest 92516 with title, description, objectives, location, timestamp, and
completion. No historical text was invented or backfilled.

Spec 2 is in progress. Its Rust parser read the real save without executing Lua:
71 events added, zero dropped, then zero added and 71 duplicates on re-import.
Read-only discovery passed all four checks and found one SavedVariables file.
An offline provider produced a recap; no cloud-generated recap is claimed.
The native Tauri/React UI, selected design, app packaging, and live Bedrock
proof remain outstanding. See the Spec 2 checklist for the current scope.
