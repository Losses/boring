package trytail;

/**
	Try-tail observation fixture (task t-mum2ad8j-wgf4): when a try prefix always
	throws, the "tail value" (the block-tail expression after the throw, at the end
	of the try body block) must not execute at the init / return / handler positions
	of the try expression.

	Four always-throwing prefixes (P1..P4) × three tail-value positions
	(init/ret/handler) = 12 independent shapes. Each shape returns a
	discriminable value:

	- authored oracle: tail value unreachable → returns the catch value
	  (init/ret = 1, handler = 3);
	- if any emitter makes the tail value reachable (truncation loss, tail-value
	  hoisting, order reversal), the return value becomes the tail value 99,
	  differing from the authored expected row.

	Prefix classification:
	- p1 single-layer throw: mustThrow(..) in the try body block directly
	  followed by tail value 99.
	- p2 nested try: the inner try in the body always throws and its handler
	  re-throws (the inner handler itself has unreachable tail value 87), the
	  outer tail value 99 follows the inner try.
	- p3 dual-branch throw: both arms of if/else in the body each throw,
	  followed by tail value 99.
	- p4 block-wrapped throw: a { mustThrow(..); } block is embedded first in
	  the body, followed by tail value 99.

	Note: this fixture does not use trace/Console (readonly-alias discipline:
	printing is done by each target's authored harness); all discrimination goes
	through the return value.
**/
enum TryTailFault {
	Single(tag:String);
}

class TryTailException extends haxe.Exception {
	public final fault:TryTailFault;

	public function new(fault:TryTailFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(_fault:TryTailFault):String {
		return switch (_fault) {
			case Single(tag): tag;
		};
	}
}

class TryTailOracle {
	public static function mustThrow(tag:String):Void {
		throw new TryTailException(TryTailFault.Single(tag));
	}

	// ---------------------------------------------------------- P1 single-layer throw

	public static function p1Init():Int {
		var v = try {
			mustThrow("p1-init");
			99;
		} catch (e:TryTailException) {
			1;
		}
		return v;
	}

	public static function p1Ret():Int {
		return try {
			mustThrow("p1-ret");
			99;
		} catch (e:TryTailException) {
			1;
		}
	}

	public static function p1Handler():Int {
		var v = 0;
		try {
			mustThrow("p1-handler");
		} catch (e:TryTailException) {
			final h = try {
				throw new TryTailException(e.fault);
				99;
			} catch (e2:TryTailException) {
				3;
			}
			v = h;
		}
		return v;
	}

	// ---------------------------------------------------------- P2 nested try

	public static function p2Init():Int {
		var v = try {
			try {
				mustThrow("p2-init");
			} catch (e:TryTailException) {
				throw new TryTailException(e.fault);
			}
			99;
		} catch (e:TryTailException) {
			1;
		}
		return v;
	}

	public static function p2Ret():Int {
		return try {
			try {
				mustThrow("p2-ret");
			} catch (e:TryTailException) {
				throw new TryTailException(e.fault);
			}
			99;
		} catch (e:TryTailException) {
			1;
		}
	}

	public static function p2Handler():Int {
		var v = 0;
		try {
			try {
				mustThrow("p2-handler");
			} catch (e:TryTailException) {
				throw new TryTailException(e.fault);
			}
			v = 98; // prefix always throws: this assignment is unreachable
		} catch (e:TryTailException) {
			final h = try {
				throw new TryTailException(e.fault);
				99;
			} catch (e2:TryTailException) {
				3;
			}
			v = h;
		}
		return v;
	}

	// ---------------------------------------------------------- P3 dual-branch throw

	public static function p3Init():Int {
		var coin = true;
		var v = try {
			if (coin) {
				mustThrow("p3-init-a");
			} else {
				mustThrow("p3-init-b");
			}
			99;
		} catch (e:TryTailException) {
			1;
		}
		return v;
	}

	public static function p3Ret():Int {
		var coin = true;
		return try {
			if (coin) {
				mustThrow("p3-ret-a");
			} else {
				mustThrow("p3-ret-b");
			}
			99;
		} catch (e:TryTailException) {
			1;
		}
	}

	public static function p3Handler():Int {
		var coin = true;
		var v = 0;
		try {
			if (coin) {
				mustThrow("p3-handler-a");
			} else {
				mustThrow("p3-handler-b");
			}
		} catch (e:TryTailException) {
			final h = try {
				throw new TryTailException(e.fault);
				99;
			} catch (e2:TryTailException) {
				3;
			}
			v = h;
		}
		return v;
	}

	// ---------------------------------------------------------- P4 block-wrapped throw

	public static function p4Init():Int {
		var v = try {
			{
				mustThrow("p4-init");
			}
			99;
		} catch (e:TryTailException) {
			1;
		}
		return v;
	}

	public static function p4Ret():Int {
		return try {
			{
				mustThrow("p4-ret");
			}
			99;
		} catch (e:TryTailException) {
			1;
		}
	}

	public static function p4Handler():Int {
		var v = 0;
		try {
			{
				mustThrow("p4-handler");
			}
		} catch (e:TryTailException) {
			final h = try {
				throw new TryTailException(e.fault);
				99;
			} catch (e2:TryTailException) {
				3;
			}
			v = h;
		}
		return v;
	}

	/**
		js-only oracle main: prints 12 discrimination lines, from which the authored
		expected is derived (tail value unreachable → catch value). native targets
		keep an empty main; printing is done by the authored harness.
	**/
	public static function main():Void {
		#if js
		std.Console.log("p1-init=" + p1Init());
		std.Console.log("p1-ret=" + p1Ret());
		std.Console.log("p1-handler=" + p1Handler());
		std.Console.log("p2-init=" + p2Init());
		std.Console.log("p2-ret=" + p2Ret());
		std.Console.log("p2-handler=" + p2Handler());
		std.Console.log("p3-init=" + p3Init());
		std.Console.log("p3-ret=" + p3Ret());
		std.Console.log("p3-handler=" + p3Handler());
		std.Console.log("p4-init=" + p4Init());
		std.Console.log("p4-ret=" + p4Ret());
		std.Console.log("p4-handler=" + p4Handler());
		#end
	}
}
