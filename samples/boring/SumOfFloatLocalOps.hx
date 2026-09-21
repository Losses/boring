package boring;

#if kotlin_output
using std.Functional;

/**
 * sumOfFloat written inside a local function body. The collection-pipeline
 * expander (docs/specs/macros/01-functional-idiom-expansion.md, position
 * rule) does not descend into function literals, so this shape survives
 * the expansion and reaches the Kotlin emitter's sumOfFloat rendering
 * (packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx). The
 * selector widens to Double and the closing narrowing is the binary32
 * module real only (feature spec 23 ruling 2).
 */
class SumOfFloatLocalOps {
    /** The plain sum, accumulated inside a local function. */
    public static function total(values:Array<Float>):Float {
        function accumulate():Float {
            return values.sumOfFloat(function(value:Float):Float {
                return value;
            });
        }
        return accumulate();
    }

    /** A weighted sum, accumulated inside a local function. */
    public static function weighted(values:Array<Float>, weight:Float):Float {
        function accumulate():Float {
            return values.sumOfFloat(function(value:Float):Float {
                return value * weight;
            });
        }
        return accumulate();
    }
}
#else
class SumOfFloatLocalOps {}
#end
