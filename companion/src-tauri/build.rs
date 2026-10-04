fn main() {
    // Only generate the Tauri context/ACL schemas for the desktop binary. A plain
    // `cargo test` of the core library leaves this a no-op (and never reads
    // tauri.conf.json), so the library build stays free of Tauri.
    if std::env::var_os("CARGO_FEATURE_DESKTOP").is_some() {
        tauri_build::build();
    }
}
