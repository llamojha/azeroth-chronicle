# Power: WoW Addon Development

Reusable knowledge for building and maintaining WoW: Forever addons. Referenced
by the `wow-addon-developer` agent and the journey-capture spec.

## `.toc` structure

```
## Interface: <build interface number>   -- MUST match the target client build
## Title: <addon name>
## Notes: <one-line description>
## Author: <author>
## Version: <semver>
## SavedVariables: <AccountLevelVarName>          -- account-wide
## SavedVariablesPerCharacter: <PerCharVarName>    -- per character (avoid here)
<file1>.lua
<file2>.lua
```

- Account-level `SavedVariables` gives ONE predictable file with characters keyed
  inside — preferred for Azeroth Chronicle.
- The `Interface` number is build-specific. A wrong number marks the addon
  out-of-date (still loadable if "Load out of date AddOns" is on, but verify).

## SavedVariables mechanics

- The client serializes the declared global(s) to
  `WTF/Account/<ACCOUNT>/SavedVariables/<AddonName>.lua` on `/reload`, logout, or
  clean shutdown — NOT continuously and NOT in realtime.
- On next load the client deserializes the file back into the global before
  `PLAYER_LOGIN` (available reliably by `PLAYER_LOGIN`, not at file-parse time).
- Only data survives: nested tables, strings, numbers, booleans, nil. No
  functions, no upvalues, no metatables.

## Event lifecycle

- Create a `Frame`, `RegisterEvent(name)`, and `SetScript("OnEvent", fn)`.
- Common events: `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `QUEST_ACCEPTED`,
  `QUEST_LOG_UPDATE`, `QUEST_TURNED_IN`, `QUEST_COMPLETE`, `ZONE_CHANGED*`.
- Event argument signatures vary by client build — guard and verify. e.g.
  `QUEST_ACCEPTED` may pass a log index and/or a questID depending on build.

## Quest APIs (verify per build)

- Classic-era: `GetQuestLogTitle(index)`, `GetQuestLogQuestText()`,
  `SelectQuestLogEntry(index)`.
- Modern: `C_QuestLog.*`, `C_QuestLog.GetInfo`, `GetQuestID()`.
- NEVER assume which set exists. Probe with guarded calls and fall back
  gracefully; missing metadata must not error.

## Event-driven Lua patterns

- Keep handlers small; dispatch via an `event -> function` switch.
- Debounce noisy events (e.g. `QUEST_LOG_UPDATE`) — resolve pending work rather
  than acting on every fire.
- Keep in-memory runtime state separate from the persisted SavedVariable.

## Sandbox limitations

- No arbitrary filesystem writes, no network, no OS access. Persistence = only
  SavedVariables.
- `C_Timer.After` is the only scheduling primitive.
- Tainting: avoid touching protected/secure frames; this addon reads unit/quest
  info only, which is safe.

## Forever compatibility

- Target the currently available Forever client/API surface.
- Prefer documented APIs present in the target build; when an API's presence is
  uncertain, guard it (`API and API(...)`) and provide a fallback.
- Confirm the `Interface` number against the running build before shipping.
