package registry;
class StringTools {
 public static function startsWith(s:String,p:String):Bool return s.substring(0,p.length)==p;
 public static function endsWith(s:String,p:String):Bool return p.length<=s.length && s.substring(s.length-p.length)==p;
 public static function has(a:Array<String>,x:String):Bool { for(i in 0...a.length) if(a[i]==x) return true; return false; }
 public static function trim(s:String):String { var a=0; var b=s.length; while(a<b && isSpace(s.charCodeAt(a))) a=a+1; while(b>a && isSpace(s.charCodeAt(b-1))) b=b-1; return s.substring(a,b); }
 static function isSpace(c:Null<Int>):Bool return c==32 || c==9 || c==10 || c==13;
 public static function indexOf(s:String, sep:String):Int { for(i in 0...s.length) if(s.substring(i,i+1)==sep) return i; return -1; }
}
