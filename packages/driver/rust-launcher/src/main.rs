use boring_driver::driver::main::Main;

fn main() {
    if let Err(error) = Main::main_main() {
        eprintln!("Error: {error}");
        std::process::exit(1);
    }
}
