package registry;

@:jsRequire("node:fs")
extern class Fs {
	static function existsSync(path:String):Bool;
	static function statSync(path:String):Stats;
	static function readdirSync(path:String):Array<String>;
	static function readFileSync(path:String, encoding:String):String;
	static function writeFileSync(path:String, data:String, encoding:String):Void;
	static function mkdirSync(path:String, options:MkdirOptions):Void;
}
@:jsRequire("node:path")
extern class Path {
	static function join(a:String, b:String, ?c:String, ?d:String, ?e:String):String;
	static function dirname(path:String):String;
}
extern class Stats { function isDirectory():Bool; }
extern class MkdirOptions { var recursive:Bool; }
extern class Env { @:native("GITHUB_TOKEN") var githubToken:Null<String>; }
@:native("process") extern class NodeProcess {
	static var argv:Array<String>;
	@:native("process.env") static var env:Env;
	static function exit(code:Int):Void;
}
@:native("console") extern class Console { static function error(message:String):Void; }
