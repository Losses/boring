use cmpgen::comparison::UnusedParamKeyCase;

fn main() {
    let name = std::env::args().nth(1).unwrap_or_default();
    let value = match name.as_str() {
        "unused-param-key" => UnusedParamKeyCase::unused_param_key_case_observe(),
        _ => {
            eprintln!("unknown case: {name}");
            std::process::exit(2);
        }
    };
    println!("{}", value.to_utf8_lossy());
}
