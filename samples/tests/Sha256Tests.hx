package tests;

import haxe.crypto.Sha256;
import haxe.io.Bytes;
import std.Test;

class Sha256Tests {
    @:test("hashes the empty byte sequence")
    public static function empty():Void {
        Test.equals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Sha256TestSupport.digestHex(Sha256.make(Sha256TestSupport.zeroes(0))));
    }

    @:test("hashes abc")
    public static function abc():Void {
        final bytes = Bytes.alloc(3);
        bytes.set(0, 97);
        bytes.set(1, 98);
        bytes.set(2, 99);
        Test.equals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", Sha256TestSupport.digestHex(Sha256.make(bytes)));
    }

    @:test("matches one-shot and incremental blocks")
    public static function incremental():Void {
        final bytes = Sha256TestSupport.zeroes(64);
        final oneShot = Sha256.make(bytes);
        final hash = new Sha256();
        hash.update(bytes.sub(0, 17));
        hash.update(bytes.sub(17, 23));
        hash.update(bytes.sub(40, 24));
        Test.equals("f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b", Sha256TestSupport.digestHex(oneShot));
        Test.equals(Sha256TestSupport.digestHex(oneShot), Sha256TestSupport.digestHex(hash.digest()));
    }
}
