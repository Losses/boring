package registry;

class StringTools {
 public static function startsWith(s:String, prefix:String):Bool return s.substring(0,prefix.length)==prefix;
 public static function endsWith(s:String, suffix:String):Bool return suffix.length<=s.length && s.substring(s.length-suffix.length)==suffix;
 public static function trim(s:String):String { var a=0; var b=s.length; while(a<b && " \t\r\n".indexOf(s.charAt(a))>=0) a=a+1; while(b>a && " \t\r\n".indexOf(s.charAt(b-1))>=0) b=b-1; return s.substring(a,a+b-a); }
}
