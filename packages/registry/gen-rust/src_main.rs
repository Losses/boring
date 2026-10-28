//! Thin binary entry point for the registry tool.
fn main() {
    match registry_tool::registry::main::Main::main_main() {
        Ok(()) => {}
        Err(e) => {
            eprintln!("{}", e);
            std::process::exit(1);
        }
    }
}
