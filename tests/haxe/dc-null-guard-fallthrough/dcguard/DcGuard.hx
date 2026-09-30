package dcguard;

/**
	Minimal discriminator for local non-null promotion after a
	fall-through `if (x == null) { ... }` guard (observation only; no
	Haxe `trace` — the harness prints, mirroring the readonly-alias
	fixture discipline).

	p2 is the discriminator: the guard body does NOT exit, so `s` may
	still be null on the fall-through path. Correct Dart emit is
	`s!.length` (requiredValueText). A backend that promotes `s` after
	the non-terminating guard emits `s.length` and the Dart analyzer
	rejects the file (receiver can be null).

	p7 is the positive control: the guard body returns, so both the
	Haxe flow fact and Dart's own flow analysis know `t` is non-null
	afterwards; `t.length` without `!` is correct there.

	p8 re-assigns the local (to a nullable ternary) after the
	fall-through guard, then uses it: the bogus promotion must not
	survive the re-assignment either.

	p9 reads the guarded local inside a closure: a stale promotion
	leaking past `functionLiteral` would emit `s.length` there and
	the analyzer rejects the file.

	p10 isolates the render-time re-assignment surface on top of a
	TERMINATING guard: the promotion at the guard is legitimate, but
	`s` is re-assigned to a nullable ternary afterwards, so the use
	must be `s!.length` again. A promotion that never observes the
	render-time write emits bare `s.length` (analyzer error).

	p11 isolates the closure-leak surface on top of a TERMINATING
	guard: the promotion is legitimate in straight-line code, but a
	closure body must start from a clean promotion slate, so the
	read inside `f` must be `s!.length` too.
**/
class DcGuard {
	public static function p2FallThrough(flag:Bool):Int {
		var s:Null<String> = flag ? "hello" : null;
		if (s == null) {
			var unused = 1;
		}
		return s.length;
	}

	public static function p7TerminatingGuard(flag:Bool):Int {
		var t:Null<String> = flag ? "world" : null;
		if (t == null) {
			return -1;
		}
		return t.length;
	}

	public static function p8GuardThenReassign(flag:Bool):Int {
		var s:Null<String> = flag ? "ab" : null;
		if (s == null) {}
		s = flag ? "xy" : null;
		return s.length;
	}

	public static function p9ClosureAfterGuard(flag:Bool):Int {
		var s:Null<String> = flag ? "abcd" : null;
		if (s == null) {}
		final f = () -> s.length;
		return f();
	}

	public static function p10TerminateGuardThenReassign(flag:Bool):Int {
		var s:Null<String> = flag ? "ab" : null;
		if (s == null) {
			return -1;
		}
		s = flag ? "xy" : null;
		return s.length;
	}

	public static function p11TerminateGuardThenClosure(flag:Bool):Int {
		// The backend emits the captured local as final (never
		// reassigned), so the leak shows up as a redundant `!` emit
		// rather than an error here; p10 covers the error-level case.
		var s:Null<String> = flag ? "abcd" : null;
		if (s == null) {
			return -1;
		}
		final f = () -> s.length;
		return f();
	}

	public static function run():String {
		final a = p2FallThrough(true);
		final b = p7TerminatingGuard(true);
		final c = p8GuardThenReassign(true);
		final d = p9ClosureAfterGuard(true);
		final e = p10TerminateGuardThenReassign(true);
		final f = p11TerminateGuardThenClosure(true);
		return "p2=" + a + "\np7=" + b + "\np8=" + c + "\np9=" + d
			+ "\np10=" + e + "\np11=" + f;
	}

	static function main() {
	}
}
