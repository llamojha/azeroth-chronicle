# Example outputs

Real, grounded sample outputs generated from an imported Azeroth Chronicle save
(character *Willpala*, a Level 13 Undead Paladin on a WoW: Forever Classic Beta
realm — 244 captured events across two days).

| File | Produced by | What it is |
|---|---|---|
| `story-willpala.md` | `journey-storyteller` agent / `journey-report` skill | A narrative retelling of the recorded journey — chapters by day. Tone is dramatized; every place, quest, and level is drawn from captured events. Nothing is invented. |
| `lore-willpala.md` | `journey-loremaster` agent | A lore compendium built **only** from the in-game quest text the addon captured (titles, descriptions, objectives) — 44 of 56 quests had text. These are custom-realm lands with no outside canon, so no external lore is imported. |

These are illustrative, not fixtures — the agents in `.kiro/agents/` regenerate
equivalents from whatever a user imports. Live outputs are written to
`companion/exports/` (gitignored); these copies are committed as references.

Grounding rule throughout: captured events only; a quest accepted but not
completed is never shown as done; missing quest text is flagged, never filled in.
