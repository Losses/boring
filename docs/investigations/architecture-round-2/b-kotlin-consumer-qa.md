# B: Kotlin local presence candidate review

The coordinator regenerated Kotlin from the isolated B checkout's current
source. Haxe exited zero. The fixture output checker exited one: 20 assertions
passed, while the nested guarded local read failed. The generated nested
function tests value != null and then emits a safe call followed by a
non-null assertion. The authored expectation is a direct value.read call.
This is a failed consumer migration assertion even though the existing
Kotlin compilation and execution report succeeded.

The emitter's TFunction branch calls functionLiteral while the outer
prepared body remains active. functionLiteral changes the return type but
does not enter the source facts stored for the literal body. The source
analysis provides nestedAt for that body. The executor should connect the
nested facts to a nested prepared body, restore the outer emitter state after
rendering, and prove that the guarded read consumes its own occurrence. A
branch or parameter fact from the enclosing function must not leak into the
literal.

Acceptance requires a fresh generation, the normal checker and its mutation
control, Kotlin compilation and execution, and an inspection of compiler
warnings. Keep the direct guarded-read assertion; weakening it would hide the
failure. Review the remaining source queries with no consumer, the default
parameter entry rule, and occurrence identity through fusion, loop, and
trailing-block transformations. Reproduce the payload enum defect against
baseline bytes before treating the candidate's passing enum checks as a fix.

Before any isolated fixture enters the coordinator checkout, rename its old
generic fixture labels to the actual observed behavior and update all paths,
commands, and expected stage identities. The coordinator's terminology scan
must remain clear after integration.
