package tests;

import registry.CoreException;
import registry.Core;
import std.Test;

using StringTools;

class RegistryParseArgsSupport {
 public static function message(argv:Array<String>):String {
  var text = "";
  try {
   Core.parseArgs(argv);
  } catch (e:CoreException) {
   text = e.message;
  }
  return text;
 }
}

class RegistryParseArgsTests {

 @:test("parseArgs reports missing required flags")
 public static function missingRequired():Void {
  var text = RegistryParseArgsSupport.message(["--tree", "tree", "--output", "site"]);
  Test.equals(true, text.startsWith("required flags missing"));
 }

 @:test("parseArgs reports help usage")
 public static function help():Void {
  var text = RegistryParseArgsSupport.message(["--help", "value"]);
  Test.equals("usage: generate --tree <dir> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>]", text);
 }

 @:test("parseArgs reports unknown flags")
 public static function unknown():Void {
  var text = RegistryParseArgsSupport.message(["--wat", "value"]);
  Test.equals(true, text.startsWith("unknown flag"));
 }
}
