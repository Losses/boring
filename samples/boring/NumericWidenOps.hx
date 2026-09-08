package boring;

class NumericWidenOps {
    static function intExpr():Int {
        return 2;
    }

    public static function operandFloat():Float {
        return 1.5 + intExpr();
    }

    public static function operandDouble():Float {
        return intExpr() + 1.5;
    }

    public static function returnFloat():Float {
        return intExpr();
    }

    public static function returnDouble():Float {
        return (intExpr());
    }

    public static function assignFloat():Float {
        var value:Float = 0.5;
        value = intExpr();
        return value;
    }

    public static function assignDouble():Float {
        var value:Float = 0.5;
        value = (intExpr());
        return value;
    }
}
