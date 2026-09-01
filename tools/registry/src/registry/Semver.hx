package registry;

typedef Version = { major:Int, minor:Int, patch:Int, pre:Array<String> };
enum SemverFault { InvalidVersion(label:String, version:String); }
class SemverException extends haxe.Exception {
 public final error:SemverFault;
 public function new(fault:SemverFault) { this.error = fault; super(SemverException.describe(fault)); }
 static function describe(f:SemverFault):String { var result=""; switch(f) { case InvalidVersion(label, version): result+=label+": version "+version+" is outside semver"; } return result; }
}
class Semver {
 static function intOf(x:String):Int { final v=Std.parseInt(x); return v==null?0:v; }
 static function validNumeric(x:String):Bool { if(x.length==0)return false;if(x.length>1&&x.charAt(0)=="0")return false;for(i in 0...x.length){var c=x.charCodeAt(i);if(c<48||c>57)return false;}return true; }
 static function validIdentifier(x:String):Bool { if(x.length==0)return false;for(i in 0...x.length){var c=x.charCodeAt(i);if(!((c>=48&&c<=57)||(c>=65&&c<=90)||(c>=97&&c<=122)||c==45))return false;}return true; }
 static function validIdentifiers(x:String):Bool {var a=x.split(".");for(i in 0...a.length)if(!validIdentifier(a[i]))return false;return true;}
 public static function parse(version:String):Null<Version> {
  var core=version, dash=version.indexOf("-"), plus=version.indexOf("+");
  if(plus>=0){if(dash>=0&&plus<dash)return null;core=version.substr(0,plus);if(!validIdentifiers(version.substr(plus+1)))return null;}
  var pre:Array<String>=new Array<String>();if(dash>=0){core=version.substr(0,dash);var end=plus>=0?plus:version.length;if(!validIdentifiers(version.substr(dash+1,end-dash-1)))return null;pre=version.substr(dash+1,end-dash-1).split(".");}
  var parts=core.split(".");if(parts.length!=3||!validNumeric(parts[0])||!validNumeric(parts[1])||!validNumeric(parts[2]))return null;
  return {major:intOf(parts[0]),minor:intOf(parts[1]),patch:intOf(parts[2]),pre:pre};
 }
 public static function require(version:String, label:String):Version {
  final v=parse(version); if(v==null) throw new SemverException(InvalidVersion(label, version)); return v;
 }
 public static function isPrerelease(version:String):Bool { final v=parse(version); return v != null && v.pre.length > 0; }
 static function pre(a:Array<String>, b:Array<String>):Int {
  if(a.length==0 && b.length==0) return 0; if(a.length==0) return 1; if(b.length==0) return -1;
  final n = a.length < b.length ? a.length : b.length;
  for(i in 0...n) { final x=a[i], y=b[i], xd=validNumeric(x), yd=validNumeric(y); if(xd&&yd) { final d=intOf(x)-intOf(y); if(d!=0)return d; } else if(xd!=yd) return xd ? -1 : 1; else if(x!=y) return x<y ? -1 : 1; }
  return a.length-b.length;
 }
 public static function compare(a:String,b:String):Int { final x=require(a,"sort"), y=require(b,"sort"); if(x.major!=y.major)return x.major-y.major; if(x.minor!=y.minor)return x.minor-y.minor; if(x.patch!=y.patch)return x.patch-y.patch; return pre(x.pre,y.pre); }
}
