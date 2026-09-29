---
inclusion: always
---

# Product

Azeroth Chronicle is a personal memory system for a WoW character.

The MVP exists to prove one flow:

    Play -> Capture -> Import -> Journal -> Recap.

Do not expand scope unless required for this flow.

Prefer boring, deterministic implementations.

The WoW addon collects facts.
The companion interprets them.

Never require cloud infrastructure for functionality that can remain local.

## Positioning

Not "an addon that remembers completed quests" (commodity). It is a **personal
memory for your World of Warcraft character**: the addon is the telemetry layer,
the companion is where the product becomes differentiated.

## The core distinction

Always separate:

- **WHAT HAPPENED TO ME** — from captured gameplay, authoritative for the
  character's journey.
- **WHAT WARCRAFT LORE SAYS** — may later come from external sources, must stay
  clearly distinguishable from player history.

## Out of scope for the MVP

Auth, accounts, cloud, sync, Windows/Linux, mobile, podcasts, TTS, social,
Discord, screenshots, lore DB, wiki ingestion, vectors/embeddings/RAG, NPC
graph, item/achievement history, combat/movement logging, maps, multi-agent,
plugin architecture. If a feature does not directly serve
`Play -> Capture -> Import -> Journal -> Recap`, it is out of scope.
