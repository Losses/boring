use std::cell::RefCell;
use std::fs::OpenOptions;
use std::io::Write;

thread_local! {
    static CURRENT_TEST: RefCell<Option<String>> = RefCell::new(None);
}

// Host edges of the test runtime (P6): the runner state, the language
// raise, and the result-file edge. The assertion checks and canonical
// formatting live in runtime.TestCore, compiled beside this module.
pub fn current_test_id() -> String {
    CURRENT_TEST.with(|cur| cur.borrow().clone().unwrap_or_default())
}

// The wall-clock budget of one test in milliseconds, read from the
// environment on every run and never at generation time, so one
// generated tree serves every budget. A value that is absent,
// unparsable, or not positive falls back to 5000. The runner carries
// no timer of its own: it reports the test a harness stopped, so this
// check is the only timeout a body that returned late is caught by.
fn timeout_budget_ms() -> u128 {
    let parsed = std::env::var("BORING_TEST_TIMEOUT_MS")
        .ok()
        .and_then(|raw| raw.trim().parse::<u128>().ok());
    match parsed {
        Some(value) if value > 0 => value,
        _ => 5000,
    }
}

// A test this target excludes (feature spec 19): the entry does not
// run the body and writes the not-applicable record instead, so the
// id stays in the cross-target set.
pub fn record_not_applicable(id: &str, name: &str) {
    record_result(id, name, "not_applicable", None);
}

pub fn run<F: FnOnce()>(id: &str, name: &str, body: F) {
    CURRENT_TEST.with(|cur| {
        *cur.borrow_mut() = Some(id.to_string());
    });
    let budget_ms = timeout_budget_ms();
    let started_at = std::time::Instant::now();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(body));
    CURRENT_TEST.with(|cur| {
        *cur.borrow_mut() = None;
    });
    match result {
        Ok(_) => {
            if started_at.elapsed().as_millis() >= budget_ms {
                // A body that returned at or past the budget raises
                // through the same path as a failed assertion: the fail
                // line carries the timeout message and the raise travels
                // on, so the runner reports the test as failed too.
                let msg = format!("this test timed out after {}ms (body took {}ms)", budget_ms, started_at.elapsed().as_millis());
                record_result(id, name, "fail", Some(&msg));
                std::panic::resume_unwind(Box::new(msg));
            }
            record_result(id, name, "pass", None);
        }
        Err(err) => {
            let msg = if let Some(s) = err.downcast_ref::<String>() {
                s.clone()
            } else if let Some(s) = err.downcast_ref::<&str>() {
                s.to_string()
            } else {
                "test panicked".to_string()
            };
            record_result(id, name, "fail", Some(&msg));
            std::panic::resume_unwind(err);
        }
    }
}

fn record_result(id: &str, name: &str, verdict: &str, message: Option<&str>) {
    // The resident builds the record line; this module only writes it.
    let json_line = if verdict == "not_applicable" {
        crate::runtime::test_core::TestCore::test_core_not_applicable_line(crate::runtime::u_string::UString::from(id).as_ustr(), crate::runtime::u_string::UString::from(name).as_ustr())
    } else {
        crate::runtime::test_core::TestCore::test_core_result_line(
            crate::runtime::u_string::UString::from(id).as_ustr(),
            crate::runtime::u_string::UString::from(name).as_ustr(),
            verdict == "fail",
            crate::runtime::u_string::UString::from(message.unwrap_or("")).as_ustr(),
        )
    };
    let file_path = std::env::var("BORING_TEST_RESULTS").unwrap_or_else(|_| "out/test-results/rust.jsonl".to_string());
    if let Some(parent) = std::path::Path::new(&file_path).parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&file_path) {
        let _ = file.write_all(&json_line.as_bytes());
    }
}
