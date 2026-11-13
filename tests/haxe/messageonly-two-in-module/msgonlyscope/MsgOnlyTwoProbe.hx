package msgonlyscope;

/**
	Boundary fixture: two message-only exception classes declared in ONE Haxe
	module. The emitter keeps a module-keyed registry of message-only
	exceptions, so the module holds only the last registered class; a catch
	clause on the other class must still name its own type.
**/
class MsgOnlyFirst extends haxe.Exception {
	public function new(message:String) {
		super(message);
	}
}

class MsgOnlySecond extends haxe.Exception {
	public function new(message:String) {
		super(message);
	}
}

class MsgOnlyTwoProbe {
	/** Catch the class declared first in this module. */
	public static function catchFirst():Int {
		var v = 0;
		try {
			throw new MsgOnlyFirst("first");
		} catch (e:MsgOnlyFirst) {
			v = 1;
		}
		return v;
	}

	/** Catch the class declared second in this module. */
	public static function catchSecond():Int {
		var v = 0;
		try {
			throw new MsgOnlySecond("second");
		} catch (e:MsgOnlySecond) {
			v = 2;
		}
		return v;
	}

	/**
		A fallible block parameter called inside a try region: the region's
		catch clause decides the block's declared error type
		(Compiler.regionErrorNameOf).
	**/
	public static function runInRegion(run:() -> Void):Int {
		var v = 0;
		try {
			run();
		} catch (e:MsgOnlyFirst) {
			v = 3;
		}
		if (v == 0) {
			throw new MsgOnlyFirst("empty");
		}
		return v;
	}

	/** Fallible on its own (the throw), so a block that calls it is a
	    fallible block and takes the region's error type. */
	public static function failFirst():Void {
		throw new MsgOnlyFirst("fail");
	}

	public static function blockCaller():Int {
		return runInRegion(() -> {
			failFirst();
		});
	}

	public static function main():Void {}
}