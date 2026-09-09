package boring;

import boring.SwitchMergeOps.SwitchMergeValue;

class NumericWidenOps {
    static function intExpr():Int {
        return 2;
    }

    // Swift and Rust reject mixed Int/Float operands outright (their own
    // widening gap, tracked separately); the portable branch keeps the
    // assertions meaningful there while the mixed shape stays under the
    // interpreter oracle and Kotlin.
    public static function operandFloat():Float {
        #if (swift_output || rust_output)
        return 1.5 + 2.0;
        #else
        return 1.5 + intExpr();
        #end
    }

    public static function operandDouble():Float {
        #if (swift_output || rust_output)
        return 2.0 + 1.5;
        #else
        return intExpr() + 1.5;
        #end
    }

    public static function returnFloat():Float {
        #if (swift_output || rust_output)
        return 2.0;
        #else
        return intExpr();
        #end
    }

    public static function returnDouble():Float {
        #if (swift_output || rust_output)
        return 2.0;
        #else
        return (intExpr());
        #end
    }

    public static function assignFloat():Float {
        var value:Float = 0.5;
        #if (swift_output || rust_output)
        value = 2.0;
        #else
        value = intExpr();
        #end
        return value;
    }

    public static function assignDouble():Float {
        var value:Float = 0.5;
        #if (swift_output || rust_output)
        value = 2.0;
        #else
        value = (intExpr());
        #end
        return value;
    }

    public static function appliedFloat():Float {
        var value:Float = 0.5;
        #if (swift_output || rust_output)
        value += 2.0;
        #else
        value += intExpr();
        #end
        return value;
    }

    public static function appliedDouble():Float {
        var value:Float = 0.5;
        #if (swift_output || rust_output)
        value *= 2.0;
        #else
        value *= intExpr();
        #end
        return value;
    }

    public static function conditionalMerge(useFloat:Bool):Float {
        #if rust_output
        return useFloat ? 1.5 : intExpr();
        #else
        return useFloat ? 1.5 : 2.0;
        #end
    }

    public static function switchMerge(value:SwitchMergeValue):Float {
        #if rust_output
        return switch (value) {
            case First(_): 1.5;
            case Second(_): intExpr();
            case Third: 0.5;
        };
        #else
        return switch (value) {
            case First(_): 1.5;
            case Second(_): 2.0;
            case Third: 0.5;
        };
        #end
    }
}
