package chk;

class Ops {
    public static function want(s:String):String return s;
    public static function viaVarOuter(o:Outer):String {
        if (o.current.fin != null)
            return want(o.current.fin);
        return "";
    }
}
