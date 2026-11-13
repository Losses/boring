package exposed;

typedef CapabilityIssue = {
    var name:String;
    var reason:String;
    var rangeStart:Int;
    var rangeEnd:Int;
}

typedef AdvanceSuspect = {
    var displayText:String;
    var advance:String;
    var reason:String;
    var rangeStart:Int;
    var rangeEnd:Int;
}

typedef Diagnostics = {
    var capabilityIssues:Array<CapabilityIssue>;
    var advanceSuspects:Array<AdvanceSuspect>;
}

typedef PlanEnvelope = {
    var plan:Array<String>;
    var diagnostics:Diagnostics;
}

typedef ShapingDecision = {
    var capabilityIssue:Null<String>;
    var reason:String;
    var displayText:String;
    var advance:Float;
    var rangeStart:Int;
    var rangeEnd:Int;
}

typedef PlainName = {
    var name:String;
}

#if !record_typedef_single
typedef NullableName = {
    var name:Null<String>;
}
#end

/**
    The shape that failed to generate on tiqian (board t-mwficz03-x636):
    capabilityIssue is Null<String>, so the guarded literal keeps a
    Null<String> name field while CapabilityIssue declares name:String. The
    typer accepts the literal against the typedef, but the anonymous
    structure's printed signature differs from the registered one, so the
    Dart and Swift shape lookups miss unless they fall back to the
    unification matching the Rust and Kotlin backends already use.
*/
class Records {
    public static function toEnvelope(decisions:Array<ShapingDecision>, zeroAdvanceEpsilonPx:Float):PlanEnvelope {
        final plan = ["p"];
        final capabilityIssues:Array<CapabilityIssue> = [];
        final advanceSuspects:Array<AdvanceSuspect> = [];
        for (d in decisions) {
            final issue = d.capabilityIssue;
            if (issue != null) {
                capabilityIssues.push({
                    name: issue,
                    reason: d.reason,
                    rangeStart: d.rangeStart,
                    rangeEnd: d.rangeEnd,
                });
            }
            if (!(Math.isFinite(d.advance) && d.advance > zeroAdvanceEpsilonPx)) {
                advanceSuspects.push({
                    displayText: d.displayText,
                    advance: Std.string(d.advance),
                    reason: d.reason,
                    rangeStart: d.rangeStart,
                    rangeEnd: d.rangeEnd,
                });
            }
        }
        return {
            plan: plan,
            diagnostics: {
                capabilityIssues: capabilityIssues,
                advanceSuspects: advanceSuspects,
            },
        };
    }

    #if record_typedef_ambiguous
    static final probeValues:Array<Null<String>> = ["known", null];

    /**
        The strictness probe: a ternary whose Null-typed arm is joined with
        null keeps a doubled Null on the field expression. That signature
        matches no registered typedef exactly and unifies with both PlainName
        and NullableName, so the shape lookup must refuse the literal rather
        than silently pick one of the four-field candidates. With
        -D record_typedef_single the rival typedef is absent, exactly one
        candidate fits, and the same literal must generate.
    **/
    public static function ambiguousPick(label:String):PlainName {
        final pick = label == "known" ? 0 : 1;
        final maybe = pick == 0 ? probeValues[pick] : null;
        return { name: maybe };
    }
    #end
}
