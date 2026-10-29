package org.tiqian.layout;

import org.tiqian.core.LayoutResult;
import org.tiqian.core.*;
import org.tiqian.protocol.PlanJson;
import org.tiqian.protocol.PlanJsonNumber;
import org.tiqian.protocol.PlanPacked;
import haxe.io.Bytes;

/** Prepared paragraph JSON serialization functions. */
class PreparedParagraphFns {
    public static function toPreparedParagraphJson(result:LayoutResult, renderEvidence:Bool = false):String {
        final plan = PlanLowering.toPlan(result, renderEvidence);
        return PlanJson.encode(plan);
    }

    public static function toPlanWithDiagnosticsJson(result:LayoutResult, renderEvidence:Bool, zeroAdvanceEpsilonPx:Float):String {
        final out:Array<String> = [];
        out.push("{\"plan\":");
        PlanJsonNumber.appendJsonString(out, toPreparedParagraphJson(result, renderEvidence));
        out.push(",\"diagnostics\":{\"capabilityIssues\":[");
        var first = true;
        final shapingDiagSrc = result.debug.shapingDecisions;
        for (di in 0...shapingDiagSrc.length) {
            final d = shapingDiagSrc[di];
            if (d.capabilityIssue != null) {
                if (!first)
                    out.push(",");
                first = false;
                out.push("{\"name\":");
                PlanJsonNumber.appendJsonString(out, d.capabilityIssue);
                out.push(",\"reason\":");
                PlanJsonNumber.appendJsonString(out, d.reason);
                out.push(",\"rangeStart\":");
                out.push(Std.string(d.range.start));
                out.push(",\"rangeEnd\":");
                out.push(Std.string(d.range.end));
                out.push("}");
            }
        }
        out.push("],\"advanceSuspects\":[");
        first = true;
        for (di in 0...shapingDiagSrc.length) {
            final d = shapingDiagSrc[di];
            if (!(Math.isFinite(d.advance) && d.advance > zeroAdvanceEpsilonPx)) {
                if (!first)
                    out.push(",");
                first = false;
                out.push("{\"displayText\":");
                PlanJsonNumber.appendJsonString(out, d.displayText);
                out.push(",\"advance\":\"");
                out.push(Math.isFinite(d.advance) ? PlanJsonNumber.ecmaJsonNumber(d.advance) : Std.string(d.advance));
                out.push("\",\"reason\":");
                PlanJsonNumber.appendJsonString(out, d.reason);
                out.push(",\"rangeStart\":");
                out.push(Std.string(d.range.start));
                out.push(",\"rangeEnd\":");
                out.push(Std.string(d.range.end));
                out.push("}");
            }
        }
        out.push("]}}");
        return out.join("");
    }

    public static function toPackedPlanBytes(result:LayoutResult):Bytes {
        final plan = PlanLowering.toPlan(result, false);
        return PlanPacked.encode(plan);
    }
}