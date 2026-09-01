package tests;

import registry.Sha1;
import std.Test;

class RegistrySha1Tests {
 @:test("SHA-1 covers empty and padding boundaries")
 public static function hashesBoundaries():Void {
  Test.equals("da39a3ee5e6b4b0d3255bfef95601890afd80709", Sha1.hex(""));
  Test.equals("c1c8bbdc22796e28c0e15163d20899b65621d65a", Sha1.hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
  Test.equals("c2db330f6083854c99d4b5bfb6e8f29f201be699", Sha1.hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
  Test.equals("f08f24908d682555111be7ff6f004e78283d989a", Sha1.hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
  Test.equals("03f09f5b158a7a8cdad920bddc29b81c18a551f5", Sha1.hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
  Test.equals("0098ba824b5c16427bd7a1122a5a442a25ec644d", Sha1.hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
  Test.equals("ee971065aaa017e0632a8ca6c77bb3bf8b1dfc56", Sha1.hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
  Test.equals("f34c1488385346a55709ba056ddd08280dd4c6d6", Sha1.hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
 }
}
