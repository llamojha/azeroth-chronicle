# Azeroth Chronicle

**A personal memory for your World of Warcraft character.**

A WoW: Forever addon captures your character's journey as structured events; a
lightweight macOS companion turns that history into a chronological journal and a
concise **"Story So Far"** recap.

The addon is the telemetry layer. The companion is where the product becomes
differentiated — the long-term goal is a persistent structured memory of
everything your character has experienced, not just another quest tracker.

## The one flow this MVP proves

```
Play → Capture → SavedVariables → Import → Timeline → Story So Far
```

```
Play WoW → accept/complete quests, change zones
   → /reload  (WoW writes AzerothChronicle.lua)
   → open the macOS companion → events import automatically
   → click "Story So Far" → get a coherent recap of your adventure
```

## Repository layout

```
addon/                     WoW: Forever addon (Lua) — OBSERVE / NORMALIZE / STORE
  AzerothChronicle.toc
  AzerothChronicle.lua     capture (the only writer of AzerothChronicleDB)
  ChronicleUI.lua          read-only in-game journal (/chronicle)
companion/                 macOS companion (Tauri: Rust backend + web frontend)
  src/                     React + Vite frontend  (scaffolded in Spec 2)
  src-tauri/               Rust backend            (scaffolded in Spec 2)
.kiro/
  specs/
    journey-capture/       Spec 1 — addon side (requirements/design/tasks)
    companion-import/      Spec 2 — companion side (requirements/design/tasks)
  steering/                product.md, architecture.md, wow-addon-development.md
  agents/                  wow-addon-developer.json
  hooks/                   test-on-save.json (v2 PostFileSave hook)
  powers/                  wow-addon-development/ (reusable addon knowledge)
```

## Architecture (boundaries)

- **SavedVariables are an ingestion boundary, not the database.** The addon
  persists only through the account-level `AzerothChronicleDB`, flushed by the
  client on `/reload`, logout, or clean exit. Not realtime.
- **The companion never writes to the WoW file.** It treats
  `AzerothChronicle.lua` as read-only, untrusted input, and **never** executes it
  with a Lua runtime — it parses the restricted table syntax as data.
- **Imports are idempotent.** Every event has a stable id, so re-importing the
  same file produces no duplicates.
- **Story So Far** is the only AI feature, abstracted behind a `StoryGenerator`
  interface (default provider: Amazon Bedrock Nova). The recap is grounded in
  captured events and never invents progression.
- **The in-game journal is a read-only viewer.** `ChronicleUI.lua` reads
  `AzerothChronicleDB` and never writes it; it groups and counts captured
  facts but adds no interpretation and no AI.

## In-game journal

Type `/chronicle` in game to open or close your character's journal (Escape
also closes it). Tabs:

- **Overview** — character, play sessions, quests completed/in progress, zones
  and areas explored, recent moments.
- **Places** — zones in the order you reached them, the areas inside them, and
  the quests you took on there.
- **Quests** — in progress and completed, with the captured objectives and
  description.
- **Timeline** — every captured moment, newest first.

The window re-reads the history each time it opens. Story So Far is not shown
in game: the companion never writes WoW files.

TODO (agreed, not yet built):

- [ ] Friends tab — needs new capture (e.g. group members) and a `schemaVersion`
      bump; "social" is out of scope for the MVP until this is approved.
- [ ] Live in-client check of `/chronicle` on WoW: Forever 1.60.1 (templates,
      scrolling, Escape-to-close).

## Development order (hard-scoped, 1–2 days)

1. **Day 1 — Journey Capture (`addon/`).** Prove real gameplay is captured into a
   well-formed `AzerothChronicle.lua`: accept + complete a quest, change zones,
   `/reload`, inspect the file. Do not build significant companion UI until this
   works.
2. **Day 2 — Companion Import (`companion/`).** Discover + parse + validate +
   dedup + timeline + Story So Far, then package/polish.

See `.kiro/specs/*/tasks.md` for the task lists.

> Interface 16001 is confirmed by the user's in-game GetBuildInfo output:
> WoW: Forever 1.60.1, build 70170 (2026-10-02). Live capture is verified:
> 71 saved events, zero duplicate IDs, and quest 92516 with captured text and completion.
>
> Spec 2 is in progress. The Rust import core runs; the desktop app is not yet
> available. See `companion/README.md` for current checks and mockups.

## Out of scope for the MVP

Auth, accounts, cloud, sync, Windows/Linux, mobile, podcasts/TTS, social,
Discord, screenshots, lore DB, wiki ingestion, vectors/embeddings/RAG, NPC
graph, item/achievement history, combat/movement logging, maps, multi-agent,
plugin architecture.

---

Built for the Kiro University Challenge.
