package throwdef;

/**
	默认参数可抛调用观察夹具（任务 t-mum0wts5-jh3m，分支
	audit/default-arg-throwing-domain）：coalescing default 的默认表达式 E
	是一个可抛静态调用（spec 22 Stage-A static-call root），用省略实参触发，
	比较 Rust 与 Swift 的函数失败域、调用标记与 try region 吸收。

	准入判定（先于一切观察，B/D 交叉审核要求）：
	- 默认位直接放调用（`p:Int = f()`）被 V16 具名错误拒绝；
- coalescing default 内的可抛调用被接受（本夹具即该源域）。

	结构分两层：
	- raw 层（resolve / callOmittedSafe / callOmittedThrowing / callExplicit）：
	  失败域的观察对象。它们的生成签名（Rust Result / Swift throws）与
	  调用标记（`?` / `try`）从生成树读取，harness 不直接调用。
	- probe 层（probeOmittedSafe / probeOmittedThrowing / probeExplicit）：
	  统一 String 返回的 try region 吸收面。region 恰好捕获本夹具异常类，
	  吸收后 probe 自身不抛；harness 只调用这一层。

	两个调用形状：
	- 省略实参：`resolve(5)` / `resolve(20)`：默认表达式求值，可抛调用
	  真实执行（5 不抛、20 抛）。
	- 显式实参：`resolve(5, 9)`：默认表达式不求值，可抛调用不执行。

	注意：本夹具不使用 trace/Console（readonly-alias 纪律：打印由各目标
	authored harness 完成），全部判别都走返回值。
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
	/** 可抛被调：seed 超过阈值抛 OverThreshold，否则返回 seed * 2。 */
	public static function throwingFallback(seed:Int):Int {
		if (seed > 10) {
			throw new ThrowingDefaultException(OverThreshold(seed));
		}
		return seed * 2;
	}

	/**
		coalescing default：`?value` 的默认表达式 E 是可抛静态调用
		`throwingFallback(seed)`（读较早参数 seed，Stage-A 语法根）。
		省略 value 时 E 求值；显式传值时 E 不求值。
	**/
	public static function resolve(seed:Int, ?value:Int):Int {
		var normalized = value == null ? throwingFallback(seed) : value;
		return normalized;
	}

	// ------------------------------------------------------ raw 调用形状

	/** 省略实参、不触发抛：resolve(5) → 默认求值 → 10。 */
	public static function callOmittedSafe():Int {
		return resolve(5);
	}

	/** 省略实参、触发抛：resolve(20) → 默认求值 → 抛 OverThreshold(20)。 */
	public static function callOmittedThrowing():Int {
		return resolve(20);
	}

	/** 显式实参：resolve(5, 9) → 默认不求值 → 9。 */
	public static function callExplicit():Int {
		return resolve(5, 9);
	}

	// ------------------------------------------- probe 层（region 吸收面）

	static function faultToken(fault:ThrowingDefaultFault):String {
		return switch (fault) {
			case OverThreshold(seed): "OverThreshold:" + seed;
		}
	}

	/** 省略实参（安全）：region 吸收后恒为 "ok:10"。 */
	public static function probeOmittedSafe():String {
		final outcome = try {
			"ok:" + callOmittedSafe();
		} catch (error:ThrowingDefaultException) {
			"caught:" + faultToken(error.fault);
		}
		return outcome;
	}

	/** 省略实参（抛）：region 吸收 → "caught:OverThreshold:20"。 */
	public static function probeOmittedThrowing():String {
		final outcome = try {
			"ok:" + callOmittedThrowing();
		} catch (error:ThrowingDefaultException) {
			"caught:" + faultToken(error.fault);
		}
		return outcome;
	}

	/** 显式实参：默认不求值 → "ok:9"。 */
	public static function probeExplicit():String {
		final outcome = try {
			"ok:" + callExplicit();
		} catch (error:ThrowingDefaultException) {
			"caught:" + faultToken(error.fault);
		}
		return outcome;
	}

	/**
		js-only oracle main：打印 3 行判别行，authored expected 即按此
		推导。native 目标保持空 main，打印由 authored harness 完成。
	**/
	public static function main():Void {
		#if js
		std.Console.log("omittedSafe=" + probeOmittedSafe());
		std.Console.log("omittedThrowing=" + probeOmittedThrowing());
		std.Console.log("explicit=" + probeExplicit());
		#end
	}
}
