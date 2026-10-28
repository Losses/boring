use crate::runtime::sorted_table::SortedTable;
use crate::runtime::u_string::UString;


#[derive(Debug, Clone, PartialEq)]
pub struct ProcessEnv {
    pub name: UString,
    pub value: UString,
}

pub fn compare_process_env(a: &ProcessEnv, b: &ProcessEnv) -> i32 {
    let cmp_name = SortedTable::sorted_table_compare_strings(a.name.as_ustr(), b.name.as_ustr());
    if cmp_name != 0 { return cmp_name; }
    let cmp_value = SortedTable::sorted_table_compare_strings(a.value.as_ustr(), b.value.as_ustr());
    if cmp_value != 0 { return cmp_value; }
    0
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcessResult {
    pub code: u32,
    pub stdout: UString,
    pub stderr: UString,
}

pub fn compare_process_result(a: &ProcessResult, b: &ProcessResult) -> i32 {
    let cmp_code = match i32::from_ne_bytes((a.code).to_ne_bytes()).cmp(&i32::from_ne_bytes((b.code).to_ne_bytes())) { core::cmp::Ordering::Less => -1, core::cmp::Ordering::Equal => 0, core::cmp::Ordering::Greater => 1 };
    if cmp_code != 0 { return cmp_code; }
    let cmp_stdout = SortedTable::sorted_table_compare_strings(a.stdout.as_ustr(), b.stdout.as_ustr());
    if cmp_stdout != 0 { return cmp_stdout; }
    let cmp_stderr = SortedTable::sorted_table_compare_strings(a.stderr.as_ustr(), b.stderr.as_ustr());
    if cmp_stderr != 0 { return cmp_stderr; }
    0
}
