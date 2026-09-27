package boring;

/**
    Mixed Int and Float addition: Haxe promotes the Int operand, while
    Swift needs the explicit widening on either side of `+`.
*/
class IntFloatAddOps {
    public static function addIntLeft(_n:Int):Float {
        #if swift_output
        return _n + 1.5;
        #else
        return 2.0 + 1.5;
        #end
    }

    public static function addIntRight(_n:Int):Float {
        #if swift_output
        return 1.5 + _n;
        #else
        return 1.5 + 2.0;
        #end
    }

    public static function addNested(_n:Int):Float {
        #if swift_output
        return 2.0 - (1.0 + _n);
        #else
        return 2.0 - (1.0 + 2.0);
        #end
    }
}
