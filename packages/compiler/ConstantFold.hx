#if (macro || reflaxe_runtime)
import haxe.macro.Expr;
import haxe.macro.Expr.Unop;
import haxe.macro.Type.TConstant;
import haxe.macro.Type.TypedExpr;

/** The result of a folded real-valued constant. */
enum FoldedReal {
    FRNan;
    FRPosInfinity;
    FRNegInfinity;
    FRZero(negative:Bool);
    FRLeastNonzero;
}

/**
    Deliberately narrow compile-time evaluation of fully literal arithmetic.

    Two rules only, each answering one diagnostic family the target
    toolchains report on intentionally-constructed NaN/infinity test code:

    - a float division whose operands are both numeric literals and whose
      divisor is zero folds to the IEEE quotient (NaN for a zero numerator,
      signed infinity otherwise). kotlinc reports the unfolded spelling as
      "division by zero" on every literal occurrence.
    - a float literal whose magnitude lies outside the target precision's
      representable range folds to the value the runtime conversion yields
      (signed zero on underflow, signed infinity on overflow). swiftc
      reports the unfolded spelling as "... underflows ... / overflows to
      inf during conversion to ...".

    Nothing else folds on purpose. General constant propagation risks a
    last-bit difference between the folded literal and the runtime-computed
    value in the f32 configuration; only the non-finite and zero edges are
    exact by definition. The sign of a zero divisor is ignored (0.0 and
    -0.0 divisors both fold to the same quotient sign); the test inputs
    contain no literal divisor that represents negative zero.
**/
class ConstantFold {
    /** Fold a literal/literal float division with a literal zero divisor. */
    public static function floatDivision(l:TypedExpr, r:TypedExpr):Null<FoldedReal> {
        final left = numericLiteral(l);
        final right = numericLiteral(r);
        if (left == null || right == null)
            return null;
        if (right.value != 0)
            return null;
        return left.value == 0 ? FRNan : (left.negative ? FRNegInfinity : FRPosInfinity);
    }

    /**
        Fold a float literal that the target precision cannot represent to
        the value its runtime conversion yields. In-range literals return
        null and keep their spelling.
     */
    public static function outOfRangeLiteral(source:String, isF32:Bool):Null<FoldedReal> {
        final value = Std.parseFloat(source);
        if (Math.isNaN(value))
            return null;
        final magnitude = Math.abs(value);
        if (magnitude == 0)
            return null;
        final max = isF32 ? 3.4028234663852886e+38 : 1.7976931348623157e+308;
        final minSubnormal = isF32 ? 1.401298464324817e-45 : 4.9e-324;
        final negative = value < 0 || negativeSpelling(source);
        if (magnitude > max)
            return negative ? FRNegInfinity : FRPosInfinity;
        if (magnitude < minSubnormal)
            return FRZero(negative);
        // The exact minimum subnormal is representable, but swiftc reports
        // the double-literal spelling as "underflows and loses precision"
        // during conversion to the target precision. Render it through the
        // target's leastNonzeroMagnitude constant instead, which names the
        // same value without the literal conversion. (ConstantFold)
        if (magnitude == minSubnormal)
            return FRLeastNonzero;
        return null;
    }

    /** Parse a numeric literal expression; parens, casts, metadata, and a unary minus strip. */
    static function numericLiteral(e:TypedExpr):Null<{value:Float, negative:Bool}> {
        return switch (strip(e).expr) {
            case TConst(TFloat(f)):
                final v = Std.parseFloat(f);
                if (Math.isNaN(v))
                    null;
                else
                    { value: v, negative: v < 0 || (v == 0 && negativeSpelling(f)) };
            case TConst(TInt(i)):
                { value: (i : Float), negative: i < 0 };
            case TUnop(OpNeg, _, inner):
                final n = numericLiteral(inner);
                if (n == null)
                    null;
                else
                    { value: -n.value, negative: n.value == 0 ? !n.negative : -n.value < 0 };
            case _:
                null;
        };
    }

    /** True when the source spelling carries an explicit minus sign. */
    static function negativeSpelling(source:String):Bool {
        final s = StringTools.trim(source);
        return s.charAt(0) == "-";
    }

    static function strip(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TCast(inner, _): strip(inner);
            case TMeta(_, inner): strip(inner);
            case _: e;
        };
    }
}
#end
