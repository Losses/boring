package tests;

import haxe.crypto.Sha512;
import haxe.io.Bytes;
import std.Test;

class Sha512Tests {
	@:test("hashes the empty byte sequence")
	public static function empty():Void {
		Test.equals("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e", Sha512TestSupport.hex(Sha512.make(Bytes.alloc(0))));
	}

	@:test("hashes abc")
	public static function abc():Void {
		final bytes = Bytes.alloc(3);
		bytes.set(0, 97); bytes.set(1, 98); bytes.set(2, 99);
		Test.equals("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", Sha512TestSupport.hex(Sha512.make(bytes)));
	}

	@:test("matches incremental updates")
	public static function incremental():Void {
		final bytes = Bytes.alloc(128);
		final hash = new Sha512();
		hash.update(bytes.sub(0, 31)); hash.update(bytes.sub(31, 64)); hash.update(bytes.sub(95, 33));
		Test.equals(Sha512TestSupport.hex(Sha512.make(bytes)), Sha512TestSupport.hex(hash.digest()));
	}
}
