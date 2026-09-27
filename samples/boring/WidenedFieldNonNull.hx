package boring;

/**
 * R1 regression sample (DeclaredFieldNonNull): field reads the typer
 * widens to Null<T> only because a receiver in the chain is nullable
 * render through the receiver extractions alone; a later hop must not
 * grow a second force or a safe call of its own.
 **/
class WidenedFieldNonNull {
	public var count:Int;
	public var next:WidenedFieldNonNull;

	public function new() {
		count = 1;
	}

	public static function read(r:Null<WidenedFieldNonNull>):Int {
		return r.count;
	}

	public static function readDeep(r:Null<WidenedFieldNonNull>):Int {
		return r.next.count;
	}
}
