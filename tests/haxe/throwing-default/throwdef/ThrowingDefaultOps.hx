package throwdef;

/**
	Throwable-call-in-default-argument observation fixture (task t-mum0wts5-jh3m,
	branch audit/default-arg-throwing-domain): the default expression E of a coalescing
	default is a throwable static call (spec 22 Stage-A static-call root), triggered by
	omitting the argument; compares Rust and Swift function failure domains, call
	markers, and try-region absorption.

	Admission judgment (before all observation, B/D cross-review requirement):
	- a call placed directly in the default position (`p:Int = f()`) is rejected
	  with the V16 named error;
	- a throwable call inside a coalescing default is accepted (this fixture is
	  that source domain).

	Structure in two layers:
	- raw layer (resolve / callOmittedSafe / callOmittedThrowing / callExplicit):
	  the observed objects of the failure domain. Their generated signatures
	  (Rust Result / Swift throws) and call markers (`?` / `try`) are read from
	  the generated tree; the harness does not call them directly.
	- probe layer (probeOmittedSafe / probeOmittedThrowing / probeExplicit):
	  a unified String-returning try-region absorption surface. The region catches
	  exactly this fixture's exception class; after absorption the probe itself does
	  not throw; the harness calls only this layer.

	Two call shapes:
	- omit the argument: `resolve(5)` / `resolve(20)`: the default expression is
	  evaluated and the throwable call really executes (5 does not throw, 20 throws).
	- explicit argument: `resolve(5, 9)`: the default expression is not evaluated
	  and the throwable call does not execute.

	Note: this fixture does not use trace/Console (readonly-alias discipline: printing
	is done by each target's authored harness); all discrimination goes through the
	return value.
**/
enum ThrowingDefaultFault {
	OverThreshold(seed:Int);
}

class ThrowingDefaultException extends haxe.Exception {
	public final fault:ThrowingDefaultFault;

	public function new(fault:ThrowingDefaultFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(fault:ThrowingDefaultFault):String {
		return switch (fault) {
			case OverThreshold(seed): 'throwing default over threshold: $seed';
		}
	}
}

class ThrowingDefaultOps {
	/** Throwable callee: throws OverThreshold when seed exceeds the threshold, otherwise returns seed * 2. */
	public static function throwingFallback(seed:Int):Int {
		if (seed > 10) {
			throw new ThrowingDefaultException(OverThreshold(seed));
		}
		return seed * 2;
	}

	/**
		coalescing default: the default expression E of `?value` is the throwable static
		call `throwingFallback(seed)` (reads the earlier parameter seed, Stage-A syntax
		root). When value is omitted E is evaluated; when passed explicitly E is not
		evaluated.
	**/
	public static function resolve(seed:Int, ?value:Int):Int {
		var normalized = value == null ? throwingFallback(seed) : value;
		return normalized;
	}

	// ------------------------------------------------------ raw call shapes

	/** Omit argument, no throw: resolve(5) -> default evaluation -> 10. */
	public static function callOmittedSafe():Int {
		return resolve(5);
	}

	/** Omit argument, triggers throw: resolve(20) -> default evaluation -> throws OverThreshold(20). */
	public static function callOmittedThrowing():Int {
		return resolve(20);
	}

	/** Explicit argument: resolve(5, 9) -> default not evaluated -> 9. */
	public static function callExplicit():Int {
		return resolve(5, 9);
	}

	// ------------------------------------------- probe layer (region absorption surface)

	static function faultToken(fault:ThrowingDefaultFault):String {
		return switch (fault) {
			case OverThreshold(seed): "OverThreshold:" + seed;
		}
	}

	/** Omit argument (safe): after region absorption always "ok:10". */
	public static function probeOmittedSafe():String {
		final outcome = try {
			"ok:" + callOmittedSafe();
		} catch (error:ThrowingDefaultException) {
			"caught:" + faultToken(error.fault);
		}
		return outcome;
	}

	/** Omit argument (throws): region absorption -> "caught:OverThreshold:20". */
	public static function probeOmittedThrowing():String {
		final outcome = try {
			"ok:" + callOmittedThrowing();
		} catch (error:ThrowingDefaultException) {
			"caught:" + faultToken(error.fault);
		}
		return outcome;
	}

	/** Explicit argument: default not evaluated -> "ok:9". */
	public static function probeExplicit():String {
		final outcome = try {
			"ok:" + callExplicit();
		} catch (error:ThrowingDefaultException) {
			"caught:" + faultToken(error.fault);
		}
		return outcome;
	}

	/**
		js-only oracle main: prints 3 discrimination lines, from which the authored
		expected is derived. native targets keep an empty main; printing is done by
		the authored harness.
	**/
	public static function main():Void {
		#if js
		std.Console.log("omittedSafe=" + probeOmittedSafe());
		std.Console.log("omittedThrowing=" + probeOmittedThrowing());
		std.Console.log("explicit=" + probeExplicit());
		#end
	}
}
