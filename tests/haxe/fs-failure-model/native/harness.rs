//! Native harness of the fs-failure-model probe.
//!
//! It prepares the host fixtures the observation needs (a directory used as
//! a file, a regular file used as a directory, and a directory with mode 000
//! for the permission-denied kind), calls the generated observation body, and
//! then calls the uncaught path. The uncaught failure is handled as the
//! generated Result error and surfaces as a deterministic nonzero exit status
//! with no panic (docs/specs/stdlib/17-platform-modules.md).

use std::os::unix::fs::PermissionsExt;

fn main() {
    let root = "out/fs-failure-model";
    std::fs::create_dir_all(format!("{}/read-dir", root)).unwrap();
    std::fs::create_dir_all(format!("{}/perm-dir", root)).unwrap();
    std::fs::write(format!("{}/regular-file", root), b"content").unwrap();
    std::fs::set_permissions(
        format!("{}/perm-dir", root),
        std::fs::Permissions::from_mode(0o000),
    )
    .unwrap();

    fs_failure_model::fsprobe::fs_failure_probe::FsFailureProbe::fs_failure_probe_observe();

    match fs_failure_model::fsprobe::fs_failure_probe::FsFailureProbe::fs_failure_probe_escaped() {
        Ok(text) => println!("m6|uncaught-returned|{}", text),
        Err(error) => {
            println!("m6|uncaught-error|{:?}", error);
            std::process::exit(1);
        }
    }
}
