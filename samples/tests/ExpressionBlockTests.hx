package tests;

import std.Test;

class ExpressionBlockTests {
    @:test("inline field arguments work in string concatenation")
    public static function inlineFieldArguments():Void {
        final holder = new ExpressionBlockHolder("a很长", 1, 3);
        Test.equals("<很长>", "<" + std.UString.slice(holder.text, holder.from, holder.to) + ">");
    }

    @:test("expression blocks support multiple declarations")
    public static function multipleDeclarations():Void {
        final holder = new ExpressionBlockHolder("abcdef", 1, 2);
        Test.equals("b", ExpressionBlockSupport.twoPart(holder.text, holder.from, holder.to));
    }

    @:test("expression blocks can be binary operands")
    public static function binaryOperand():Void {
        final holder = new ExpressionBlockHolder("abcdef", 1, 2);
        Test.equals(true, ExpressionBlockSupport.twoPart(holder.text, holder.from, holder.to) + "" == "b");
    }

    @:test("nested record field chains trigger the lowering")
    public static function nestedFieldChain():Void {
        final holder = new ExpressionBlockHolder("abcdef", 1, 2);
        final nested = new ExpressionBlockOuter(new ExpressionBlockInner(holder));
        Test.equals("b", std.UString.slice(nested.inner.holder.text, nested.inner.holder.from, nested.inner.holder.to));
    }

}

class ExpressionBlockSupport {
    public static inline function twoPart(text:String, from:Int, to:Int):String {
        final start = from;
        final end = to;
        return std.UString.slice(text, start, end);
    }
}

class ExpressionBlockHolder {
    public final text:String;
    public final from:Int;
    public final to:Int;

    public function new(text:String, from:Int, to:Int) {
        this.text = text;
        this.from = from;
        this.to = to;
    }
}

class ExpressionBlockInner {
    public final holder:ExpressionBlockHolder;

    public function new(holder:ExpressionBlockHolder) {
        this.holder = holder;
    }
}

class ExpressionBlockOuter {
    public final inner:ExpressionBlockInner;

    public function new(inner:ExpressionBlockInner) {
        this.inner = inner;
    }
}
