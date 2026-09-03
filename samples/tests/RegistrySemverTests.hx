package tests;
import registry.Semver;
import std.Test;
class RegistrySemverTests {
 @:test("semver orders prereleases before releases")
 public static function ordering():Void {
  Test.equals(-1,Semver.compare("1.0.0-alpha.1","1.0.0-beta"));
  Test.equals(-1,Semver.compare("1.0.0-rc.1","1.0.0"));
  Test.equals(true,Semver.isPrerelease("2.0.0-dev"));
 }
}
