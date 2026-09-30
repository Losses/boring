package trytail;

/**
	D 观察夹具（任务 t-mum2ad8j-wgf4）：try 前缀必抛时，try 表达式
	初始化 / 返回 / handler 三个位置上的「尾值」（throw 之后、try 体块
	的块尾表达式）不得执行。

	四类必抛前缀（P1..P4）× 三个尾值位置（init/ret/handler）= 12 个
	独立形状。每个形状返回一个可判别值：

	- authored oracle：尾值不可达 → 返回 catch 值（init/ret = 1，
	  handler = 3）；
	- 若任何发射器把尾值变成可达（截断丢失、尾值提升、顺序颠倒），
	  返回值会变成尾值 99，与 authored expected 行相异。

	前缀分类：
	- p1 单层 throw：try 体块内 mustThrow(..) 后直接跟尾值 99。
	- p2 嵌套 try：体块内层 try 必抛且 handler 重新 throw（内层 handler
	  自身也有不可达尾值 87），内层 try 之后是外层尾值 99。
	- p3 双分支 throw：体块内 if/else 两臂各自 throw，之后是尾值 99。
	- p4 块包装 throw：体块内先嵌一个 { mustThrow(..); } 块，块后是
	  尾值 99。

	注意：本夹具不使用 trace/Console（readonly-alias 纪律：打印由各
	目标 authored harness 完成），全部判别都走返回值。
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

	// ---------------------------------------------------------- P1 单层 throw

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

	// ---------------------------------------------------------- P2 嵌套 try

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
			v = 98; // 前缀必抛：此赋值不可达
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

	// ---------------------------------------------------------- P3 双分支 throw

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

	// ---------------------------------------------------------- P4 块包装 throw

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
		js-only oracle main：打印 12 行判别行，authored expected 即按此
		推导（尾值不可达 → catch 值）。native 目标保持空 main，打印由
		authored harness 完成。
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
