# WoW addon development Power

Package draft for Kiro, version 0.1.0. It includes an activation manifest,
WoW API MCP configuration pinned to the reviewed 0.2.0 version, and a
quest-capture and lore-review skill.

## Install and prove activation

Prerequisites: Kiro with Powers support, Node.js/npm with `npx` on PATH, and
network access for the MCP package and public documentation. No AWS credentials
are needed. Other clients require their own API flavor to be verified.

In Kiro, open Powers, choose Add Custom Power, then Import power from a folder.
Select this directory and install. This local-folder route works while the
project repository is private. Kiro namespaces bundled MCP servers; select the
Power's server when collecting evidence rather than the project-level duplicate.

Use this bounded task in Kiro:

> Use the WoW addon development Power to review Azeroth Chronicle's lore example
> against imported quest descriptions. Resolve Interface 16001 through the
> bundled MCP and search its wiki for Zephras Isle. Check unique quest coverage,
> quotations, uncertainty, and the unfinished Turncoat quest. Report source IDs
> and findings. Do not modify game files or publish anything.

Retain the Power activation indicator, MCP tool calls, and resulting review.
No paid cloud inference is needed for the WoW MCP itself; normal Kiro usage
still applies.

## Status

- [x] Manifest, bundled MCP configuration, and workflow authored.
- [ ] Install in Kiro and verify keyword activation and skill loading.
- [ ] Run the task through the installed Power and retain the result.
- [ ] Include the tested package and evidence in the final submission.

The older POWER.md is retained as historical project guidance. The skill is
self-contained and corrects its overly narrow scheduling guidance. Existing
MCP review evidence is not evidence that this newly packaged Power activated.

Packaging references checked on 2026-10-03:
[Create powers](https://kiro.dev/docs/powers/create/) and
[Install powers](https://kiro.dev/docs/powers/installation/).
