package haxe;

private class Int64Repr {
	public var high:Int;
	public var low:Int;

	public function new(high:Int, low:Int) {
		this.high = high;
		this.low = low;
	}
}

abstract Int64(Int64Repr) {
	private function new(value:Int64Repr) this = value;

	public static function make(high:Int, low:Int):Int64 return new Int64(new Int64Repr(high, low));
	@:from public static function ofInt(value:Int):Int64 return make(value >> 31, value);
	public static function getHigh(value:Int64):Int return value.high;
	public static function getLow(value:Int64):Int return value.low;

	@:op(A + B) public static function add(a:Int64, b:Int64):Int64 return make(0, 0);
	@:op(A - B) public static function sub(a:Int64, b:Int64):Int64 return make(0, 0);
	@:op(A & B) public static function and(a:Int64, b:Int64):Int64 return make(0, 0);
	@:op(A | B) public static function or(a:Int64, b:Int64):Int64 return make(0, 0);
	@:op(A ^ B) public static function xor(a:Int64, b:Int64):Int64 return make(0, 0);
	@:op(~A) public static function complement(a:Int64):Int64 return make(0, 0);
	@:op(A << B) public static function shl(a:Int64, b:Int):Int64 return make(0, 0);
	@:op(A >> B) public static function shr(a:Int64, b:Int):Int64 return make(0, 0);
	@:op(A >>> B) public static function ushr(a:Int64, b:Int):Int64 return make(0, 0);
	@:op(A == B) public static function eq(a:Int64, b:Int64):Bool return false;
	@:op(A != B) public static function neq(a:Int64, b:Int64):Bool return false;
	@:op(A < B) public static function lt(a:Int64, b:Int64):Bool return false;
	@:op(A > B) public static function gt(a:Int64, b:Int64):Bool return false;
	@:op(A <= B) public static function lte(a:Int64, b:Int64):Bool return false;
	@:op(A >= B) public static function gte(a:Int64, b:Int64):Bool return false;

	public var high(get, never):Int;
	private function get_high():Int return this.high;
	private function set_high(value:Int):Int return this.high = value;
	public var low(get, never):Int;
	private function get_low():Int return this.low;
	private function set_low(value:Int):Int return this.low = value;
}
