package xcheckscope;

import otherpkg.ModEx;
import otherpkg.ModOps;

/** Boundary fixture: the exception class and its payload enum live in another
    module than the rethrow site (uncertainty #2 of the report). */
class XModProbe {
	public static function rethrowCrossModule():Int {
		var v = 0;
		try {
			ModOps.fail("x");
		} catch (e:ModEx) {
			final h = try {
				throw new ModEx(e.fault);
				99;
			} catch (e2:ModEx) {
				7;
			}
			v = h;
		}
		return v;
	}

	public static function main():Void {}
}
