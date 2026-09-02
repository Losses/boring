package registry;
class StringTools {
 public static function startsWith(s:String,p:String):Bool return p.length<=s.length && s.substring(0,p.length)==p;
 public static function endsWith(s:String,p:String):Bool return p.length<=s.length && s.substring(s.length-p.length)==p;
 public static function has(a:Array<String>,x:String):Bool { for(i in 0...a.length) if(a[i]==x) return true; return false; }
 public static function split(s:String, sep:String):Array<String> { var out:Array<String>=[]; var start=0; for(i in 0...s.length) if(s.substring(i,i+1)==sep) { out.push(s.substring(start,i)); start=i+1; } out.push(s.substring(start)); return out; }
 public static function compare(a:String,b:String):Int { if(a==b)return 0; var n=a.length<b.length?a.length:b.length; for(i in 0...n) { var ac=codeAt(a,i),bc=codeAt(b,i); if(ac!=bc)return ac<bc?-1:1; } return a.length<b.length?-1:1; }
 public static function trim(s:String):String { var a=0; var b=s.length; while(a<b && isSpace(codeAt(s, a))) a=a+1; while(b>a && isSpace(codeAt(s, b-1))) b=b-1; return s.substring(a,b); }
 public static function codeAt(s:String, i:Int):Int { var c=s.charCodeAt(i); return c==null ? -1 : c; }
 static function isSpace(c:Int):Bool return c==32 || c==9 || c==10 || c==13;
 public static function indexOf(s:String, sep:String):Int { for(i in 0...s.length) if(s.substring(i,i+1)==sep) return i; return -1; }
}
