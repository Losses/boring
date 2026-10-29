package org.tiqian.layout;

import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.protocol.PlanJsonNumber;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphJsonNumberTestSupport {
    public static function rec(name:String):Void
        new TestTraceRecorder("PreparedParagraphJsonNumberTest").section(name);

    public static function eq(expected:String, value:Float):Void {
        final actual = PlanJsonNumber.ecmaJsonNumber(value);
        // NaN/±Infinity/±0 保持精确字符串相等；有限非零值按解析值（f32 round-trip）相等，末位容差
        if (!Math.isFinite(value) || value == 0) {
            TracedAssertions.assertEqualsString(expected, actual,
                "number token mismatch: expected '" + expected + "' got '" + actual + "'");
            return;
        }
        final expectedF32 = haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(Std.parseFloat(expected)));
        final actualF32 = haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(Std.parseFloat(actual)));
        TracedAssertions.assertEqualsFloat(expectedF32, actualF32,
            "number token mismatch (f32 round-trip): expected '" + expected + "' got '" + actual + "'");
    }
}