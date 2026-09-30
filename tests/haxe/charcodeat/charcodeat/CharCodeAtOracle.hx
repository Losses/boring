package charcodeat;

/**
	Authored observation source for the string-boundary and nullable
	`charCodeAt` source-domain task (board t-mum1qvjl-3bss).

	Subject on every shape: the ASCII literal "abcdef", six UTF-16
	units.

	Accepted shapes (six) -- established empirically against the pinned
	Haxe 4.3.7 toolchain: the plain 4.3.7 typer performs no strict
	nullability enforcement (even `var c:Int = null` typechecks), so
	BOTH the declared `Null<Int>` context and the declared `Int` context
	are source-accepted for an out-of-range `charCodeAt`. The raw
	evidence (empty diagnostics, exit 0) is recorded by the probe
	stages; probes/PCodeint.hx documents the `Int`-context shape.
	- subRev:   reversed in-range bounds, `substring(4, 2)` (start > end)
	- subHigh:  high bound past the end, `substring(4, 100)` (end > length)
	- subNeg:   negative low bound, `substring(-1, 3)` (start < 0;
		supplementary domain row)
	- codeNull: out-of-range `charCodeAt(100)` held in the declared
		`Null<Int>` context
	- codeNeg:  negative `charCodeAt(-1)` held in the declared `Null<Int>`
		context (supplementary row)
	- codeInt:  out-of-range `charCodeAt(100)` assigned to the declared
		`Int` (non-nullable) context -- source-accepted by the pinned
		typer; the shape where each target's runtime semantics for a
		miss become directly observable

	The native harnesses print the six labeled lines; a null, undefined,
	nil, or None unit value is rendered as the token `null` on every
	target so the compare stage sees display-neutral output. The Haxe JS
	oracle achieves the same token through JS null-collapse
	(`undefined == null` is true) inside an if-guard, keeping the oracle
	source free of `Std.string` on a nullable (rejected by the reflaxe
	pipeline) and of ternaries mixing `String` with `Null<Int>`
	(rejected by the pinned typer).
**/
class CharCodeAtOracle {
	/**
		Reversed in-range bounds. The Haxe std rule for `substring` swaps
		start and end when `startIndex` exceeds `endIndex`.
	**/
	public static function subRev():String {
		return "abcdef".substring(4, 2);
	}

	/**
		High bound past the end. The Haxe std rule replaces an `endIndex`
		exceeding `this.length` with `this.length`.
	**/
	public static function subHigh():String {
		return "abcdef".substring(4, 100);
	}

	/**
		Negative low bound (supplementary row). The Haxe std rule replaces
		a negative `startIndex` with 0.
	**/
	public static function subNeg():String {
		return "abcdef".substring(-1, 3);
	}

	/**
		Out-of-range unit read in the declared `Null<Int>` context.
	**/
	public static function codeNull():Null<Int> {
		var c:Null<Int> = "abcdef".charCodeAt(100);
		return c;
	}

	/**
		Negative unit read in the declared `Null<Int>` context
		(supplementary row).
	**/
	public static function codeNeg():Null<Int> {
		var c:Null<Int> = "abcdef".charCodeAt(-1);
		return c;
	}

	/**
		Out-of-range unit read assigned to the declared `Int` context.
		Accepted by the pinned Haxe 4.3.7 typer (no strict nullability
		enforcement by default); the runtime miss is carried in a
		non-nullable value on the generated targets.
	**/
	public static function codeInt():Int {
		var c:Int = "abcdef".charCodeAt(100);
		return c;
	}

	/**
		Display-neutral rendering of a nullable code unit: the token
		`null` for a miss, the decimal value for a hit. Uses only
		string concatenation (no `Std.string` on a nullable, which the
		reflaxe pipeline rejects, and no ternary whose branches mix
		`String` with `Null<Int>`, which the pinned typer rejects): in
		the Haxe JS oracle a miss is `undefined`, and `undefined == null`
		collapses to true, so the guard selects the `null` token.
	**/
	public static function codeLine(label:String, c:Null<Int>):String {
		if (c == null) return label + "null";
		return label + c;
	}

	/**
		The Haxe JS oracle entry. Native harnesses call the six shape
		functions directly and print the same labeled lines; the
		generated trees for native targets keep an empty main so the
		fixture adds no target-specific console dependency.
	**/
	public static function main():Void {
		#if js
		std.Console.log("subRev=" + subRev());
		std.Console.log("subHigh=" + subHigh());
		std.Console.log("subNeg=" + subNeg());
		std.Console.log(codeLine("codeNull=", codeNull()));
		std.Console.log(codeLine("codeNeg=", codeNeg()));
		std.Console.log(codeLine("codeInt=", codeInt()));
		#end
	}
}
