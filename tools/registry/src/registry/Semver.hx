package registry;

typedef Version = { major:Int, minor:Int, patch:Int, pre:Array<String> };
class Semver {
	static final pattern = ~/^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$/;
	public static function parse(version:String):Null<Version> {
		if(!pattern.match(version)) return null;
		final pre = pattern.matched(4);
		return {major:Std.parseInt(pattern.matched(1)), minor:Std.parseInt(pattern.matched(2)), patch:Std.parseInt(pattern.matched(3)), pre:pre == null ? [] : pre.split(".")};
	}
	public static function require(version:String, label:String):Version {
		final v=parse(version); if(v==null) throw label + ": version " + version + " is outside semver"; return v;
	}
	public static function isPrerelease(version:String):Bool { final v=parse(version); return v != null && v.pre.length > 0; }
	static function pre(a:Array<String>, b:Array<String>):Int {
		if(a.length==0 && b.length==0) return 0; if(a.length==0) return 1; if(b.length==0) return -1;
		final n = a.length < b.length ? a.length : b.length;
		for(i in 0...n) { final x=a[i], y=b[i], xd=~/^\d+$/.match(x), yd=~/^\d+$/.match(y); if(xd&&yd) { final d=Std.parseInt(x)-Std.parseInt(y); if(d!=0)return d; } else if(xd!=yd) return xd ? -1 : 1; else if(x!=y) return x<y ? -1 : 1; }
		return a.length-b.length;
	}
	public static function compare(a:String,b:String):Int { final x=require(a,"sort"), y=require(b,"sort"); if(x.major!=y.major)return x.major-y.major; if(x.minor!=y.minor)return x.minor-y.minor; if(x.patch!=y.patch)return x.patch-y.patch; return pre(x.pre,y.pre); }
}
