package boring;

/**
 * R1 regression sample (ValueArrayBindingVar): a local whose binding
 * lowers to the native [UInt8] value array keeps var even when the
 * emitter proves the binding never reassigned, because add/set write
 * the binding itself.
 **/
class BytesValueArrayVar {
	public static function touch():Int {
		var buf = haxe.io.Bytes.alloc(4);
		buf.set(0, 65);
		return buf.get(0);
	}
}
