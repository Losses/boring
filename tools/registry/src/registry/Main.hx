package registry;
@:jsRequire("node:fs") extern class Fs { static function existsSync(p:String):Bool; static function readdirSync(p:String):Array<String>; static function writeFileSync(p:String,d:String,e:String):Void; static function mkdirSync(p:String,o:Dynamic):Void; }
@:jsRequire("node:path") extern class Path { static function join(a:String,b:String):String; static function dirname(a:String):String; }
@:native("process") extern class NodeProcess { static var argv:Array<String>; }
class Main {
 static function main():Void {var a=NodeProcess.argv;var i=a.indexOf("--output");var root=a[i+1];var p=Path.join(root,"swift/identifiers");Fs.mkdirSync(Path.dirname(p),{recursive:true});Fs.writeFileSync(p,"[]\n","utf8");}
}
