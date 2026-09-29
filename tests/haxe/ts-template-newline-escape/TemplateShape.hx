package;

/** Regression shapes for template-literal newline escaping: every returned
    string leaves the generator as a template literal, so each escape the
    emitter chooses decides the runtime bytes. **/
class TemplateShape {
    public static function lf():String {
        return "l1" + "\n" + "l2";
    }

    public static function cr():String {
        return "c1" + "\r" + "c2";
    }

    public static function crlf():String {
        return "w1" + "\r\n" + "w2";
    }

    public static function backtick():String {
        return "t1" + "`" + "t2";
    }

    public static function interpolation():String {
        return "i1" + "${value}" + "i2";
    }

    public static function backslash():String {
        return "b1" + "\\" + "b2";
    }

    public static function main():Void {}
}
