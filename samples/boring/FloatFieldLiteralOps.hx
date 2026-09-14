package boring;

#if rust_output
typedef FloatFieldPair = {
    final leading:Float;
    final trailing:Float;
};

/**
    An anonymous-structure Float field written from an Int literal. Rust field
    slots are not coerced, so the literal widens into the declared Float
    domain. The named floatFieldIntLiteral rule covers the zero-literal arms.
*/
class FloatFieldLiteralOps {
    public static function pair(side:Int, total:Float):FloatFieldPair {
        if (side == 0)
            return {leading: total, trailing: 0};
        if (side == 1)
            return {leading: 0, trailing: total};
        return {leading: total / 2, trailing: total / 2};
    }
}
#else
class FloatFieldLiteralOps {}
#end
