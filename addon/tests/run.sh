#!/usr/bin/env sh
# Addon test runner. Used by the test-on-save hook and manual runs.
# From the repo root: sh addon/tests/run.sh
set -e

# Make Homebrew + luarocks-installed tools reachable in non-login shells.
export PATH="$PATH:/opt/homebrew/bin:$HOME/.luarocks/bin"

cd "$(dirname "$0")/../.." # repo root

# 1. Syntax-check the addon (fast, catches parse errors).
if command -v luac >/dev/null 2>&1; then
  echo "==> luac syntax check"
  luac -p addon/AzerothChronicle.lua
  echo "    OK"
fi

# 2. Lint IF a working luacheck is present. luacheck currently breaks on
#    Lua 5.5; skip rather than fail the whole run.
if command -v luacheck >/dev/null 2>&1; then
  echo "==> luacheck"
  luacheck addon --config .luacheckrc || echo "    (luacheck skipped/failed — non-fatal)"
fi

# 3. Unit / property tests.
if command -v busted >/dev/null 2>&1; then
  echo "==> busted"
  busted
else
  echo "==> busted not found — install with: luarocks install busted"
  exit 1
fi
