package registry;

@:jsRequire("node:fs")
extern class Fs {
  static function existsSync(path:String):Bool;
  static function statSync(path:String):Dynamic;
  static function readdirSync(path:String):Array<String>;
  static function readFileSync(path:String, encoding:String):String;
  static function writeFileSync(path:String, data:String, encoding:String):Void;
  static function mkdirSync(path:String, options:Dynamic):Void;
}
@:jsRequire("node:path")
extern class Path {
  static function join(a:String, b:String, ?c:String, ?d:String, ?e:String):String;
  static function dirname(a:String):String;
}
@:native("process") extern class NodeProcess {
  static var argv:Array<String>;
  static var env:Dynamic;
  static function exit(code:Int):Void;
}
@:native("console") extern class Console { static function error(s:String):Void; }
@:native("fetch") extern class Fetch { static function fetch(url:String, options:Dynamic):Dynamic; }
@:jsRequire("node:crypto") extern class Crypto {
  static function createHash(name:String):Dynamic;
}
