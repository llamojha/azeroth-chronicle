//! Read-only discovery probe; prints counts without account identifiers.
fn main() -> Result<(), String> {
    let path = std::env::args()
        .nth(1)
        .ok_or("Pass the WoW installation directory")?;
    let result = chronicle::discovery::discover(std::path::Path::new(&path))?;
    println!(
        "checks={} passed={} saved_files={}",
        result.checks.len(),
        result.checks.iter().filter(|c| c.passed).count(),
        result.files.len()
    );
    Ok(())
}
