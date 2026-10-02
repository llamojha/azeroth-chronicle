# Companion development

The Rust import core works. The Tauri/React desktop shell and macOS package are
not built yet. Choose a journal layout in `design-options.html` before UI work.

## Run backend checks

From the repository root:

```sh
cargo test --manifest-path companion/src-tauri/Cargo.toml -j 2
cargo clippy --manifest-path companion/src-tauri/Cargo.toml --all-targets -- -D warnings
cargo fmt --manifest-path companion/src-tauri/Cargo.toml --check
```

The current host restricts canonicalization inside its session scratch directory.
Fixture tests pass with `TMPDIR` set to an existing ignored directory at
`companion/src-tauri/target/test-tmp`. This workaround was explicitly approved;
ordinary local terminals should use their normal temporary directory.

## Inspect a save without changing it

```sh
cargo run --manifest-path companion/src-tauri/Cargo.toml --example inspect -- '/path/to/AzerothChronicle.lua'
cargo run --manifest-path companion/src-tauri/Cargo.toml --example discover -- '/path/to/World of Warcraft/_classic_beta_'
```

`inspect` reads the save as data, imports it twice in memory, and reports event
counts plus an offline recap size. It writes no cache and makes no network calls.
`discover` checks the selected folder and one level of client subdirectories,
then searches only `WTF/Account/*/SavedVariables/AzerothChronicle.lua`.

## Persistence and safety

The parser does not run Lua. It rejects expressions, calls, duplicate keys,
trailing code, excessive depth, and files larger than 32 MiB. Schema 1 is the only
supported schema today. Unknown versions preserve the existing history.

Imports keep the first event for each ID. Repeated IDs with different payloads
are counted as conflicts, not used to overwrite history. Malformed files leave
the last good state intact. Separate accounts can succeed or fail independently.
The JSON cache uses an atomic file replacement in companion-owned app data.
The desktop shell still needs to select that directory and load the cache.

## Recap providers

The default backend build includes only a deterministic offline provider.
`JourneyContext` includes the most recent 100 events and earlier captured
acceptance snapshots relevant to those completions. Missing text stays missing.

Compile the optional AWS SDK provider without invoking it:

```sh
cargo check --manifest-path companion/src-tauri/Cargo.toml --features bedrock -j 2
```

The implementation uses the [AWS Rust SDK Converse API](https://docs.aws.amazon.com/sdk-for-rust/latest/dg/rust_bedrock-runtime_code_examples.html).
Its constructor requires explicit consent to transfer character/quest data and
incur model charges. Region and model ID are supplied by the caller; the SDK
uses the configured credential chain. No credentials belong in this repository.
Requests time out after 60 seconds and refuse contexts larger than 64 KiB.
Run this synchronous provider on a blocking worker, not an async/UI thread.

No live Bedrock request has been made. Grounding instructions and offline tests
do not prove that model output is factual. Live verification remains a separate,
authorized step. The app must clearly label offline versus cloud recaps.

## Current evidence

- The real WoW save parses with 71 events and no invalid events.
- Re-import adds zero events and identifies all 71 duplicates.
- Discovery finds one save and passes four checks on the selected game client.
- Fifteen backend tests pass with `--features bedrock`, including four generated
  property tests and two offline provider tests. Clippy and formatting pass.
- No Tauri launch, rendered-app verification, or macOS package is claimed.
- No Kiro IDE Correctness evidence was produced by these Rust tests.
