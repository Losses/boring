package boring;

import std.UStringException;
import std.UStringFault;

/**
 * Try-region shapes of docs/specs/features/06-errors-and-results.md: the
 * statement, return, initializer, and handler-return positions every target
 * lowers, plus the payload and message accessors on the caught variable.
 */
class TryOps {
	static function throwingCodec(count:Int):Int {
		if (count > 10) {
			throw new VectorException(CountOverflow);
		}
		return count * 2;
	}

	/** Variant identity to number: the return-position switch every lane shares. */
	public static function classifyFault(error:VectorError):Int {
		return switch (error) {
			case BadMagic: 11;
			case CountOverflow: 12;
			case UnexpectedEof: 13;
			case TrailingBytes(remaining): 24;
		};
	}

	/** A second domain: the payload field follows the class declaration. */
	static function classifyCode(fault:UStringFault):Int {
		// Statement position: a single-case switch expression collapses
		// into a block no target lowers as a value.
		switch (fault) {
			case InvalidCodePoint(code):
				return 30 + code;
		}
	}

	/** Statement position: both arms write the same local. */
	public static function caughtStatement(count:Int):Int {
		var total = 0;
		try {
			total = total + throwingCodec(count);
		} catch (error:VectorException) {
			total = total + classifyFault(error.error);
		}
		return total;
	}

	/** Return position: the region itself is the returned value. */
	public static function regionReturn(count:Int):Int {
		return try {
			throwingCodec(count);
		} catch (error:VectorException) {
			classifyFault(error.error);
		};
	}

	/** Initializer position: the region binds a final value. */
	public static function regionValue(count:Int):Int {
		final value = try {
			throwingCodec(count);
		} catch (error:VectorException) {
			classifyFault(error.error);
		};
		return value + 1;
	}

	/** Handler return: control flow leaves through the handler only. */
	public static function handlerReturn(count:Int):Int {
		var total = 0;
		try {
			total = total + throwingCodec(count);
		} catch (error:VectorException) {
			return classifyFault(error.error);
		}
		return total;
	}

	/** Message accessor: display text derived from the variant. */
	public static function regionMessage(count:Int):String {
		final text = try {
			throwingCodec(count);
			"no fault";
		} catch (error:VectorException) {
			error.message;
		};
		return text;
	}

	/** Payload capture across the fold: the catch variable carries the variant. */
	public static function faultPayload(code:Int):Int {
		final value = try {
			throw new UStringException(UStringFault.InvalidCodePoint(code));
			0;
		} catch (error:UStringException) {
			classifyCode(error.fault);
		};
		return value;
	}
}
