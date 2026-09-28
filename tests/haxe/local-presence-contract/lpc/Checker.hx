package lpc;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import ExpressionPredicates;
import SourceLocalPresenceAnalysis;
import SourceLocalPresenceAnalysis.SourceLocalPresenceFacts;
import SourceLocalPresenceAnalysis.SourceAnalysisDiagnostic;
#end

/**
    The authored expectation table and the comparison.

    Every expectation was written from the source rules of the local presence
    contract, independently of the analyzer's answers. A row states the case,
    the row kind, the index, and the labels the observer must report. The
    comparison checks three things: every expectation has exactly one row,
    every row has an expectation, and every matched pair agrees. A coverage
    defect is a failure, so an unobserved case cannot pass silently.

    The check runs as the compile-time step that `run.hxml` invokes. It
    prints one line per observed row, then the failures, and exits nonzero
    when any check failed.
**/
class Checker {
    public static function run():Void {
        for (line in check())
            Sys.println(line);
        Sys.exit(failures.length == 0 ? 0 : 1);
    }

    public static final failures:Array<String> = [];

    /** Prepares every case, compares it against the table, and returns the
        report lines. */
    public static function check():Array<String> {
        final lines:Array<String> = [];
        final rows:Array<ObservedUse> = [];
        for (field in caseFields()) {
            final body = field.expr();
            if (body == null) {
                failures.push("case " + field.name + " has no body");
                continue;
            }
            // A method body reaches the observer as the function literal the
            // typer built for it. Its own parameters are this body's
            // parameters, so they enter `Unknown` by rule and not as outer
            // captures.
            final owned = switch (body.expr) {
                case TFunction(fn): fn.expr;
                case _: body;
            }
            final parameters = switch (body.expr) {
                case TFunction(fn): [for (argument in fn.args) {binding: argument.v.id, written: argument.v.t}];
                case _: [];
            }
            final facts = SourceLocalPresenceAnalysis.prepare({
                body: owned,
                parameters: parameters,
                outerCapturedWrites: [],
                outerSummaryKind: SourceCaptureSummaryKind.EnclosingAssignsNothing,
                outerCaptureFacts: []
            });
            collect(facts, owned, field.name, rows);
            recordCaseFacts(facts, field.name, rows);
        }
        abruptLiteralRows(rows);
        sharedNodeRows(rows);
        compare(rows);
        for (row in rows)
            lines.push(row.caseName + "|" + row.kind + row.index + "|" + row.subject + "|" + row.availability + "|" + row.knowledge + "|"
                + row.presence + "|" + row.reason);
        for (failure in failures)
            lines.push("FAIL " + failure);
        lines.push(rows.length + " observed rows against " + EXPECTATIONS.length + " authored expectations, "
            + failures.length + " failures");
        return lines;
    }

    #if macro
    static function caseFields():Array<ClassField> {
        final cls = switch (Context.getType("lpc.Cases")) {
            case TInst(c, _):
                c.get();
            case _:
                failures.push("lpc.Cases must be a class");
                null;
        }
        final out:Array<ClassField> = [];
        for (field in cls.statics.get())
            if (!isHelper(field.name))
                out.push(field);
        return out;
    }

    static function isHelper(name:String):Bool {
        return name == "use" || name == "load" || name == "checked" || name == "probe" || name == "invoke" || name == "mutate"
            || name == "widen";
    }

    static function recordCaseFacts(facts:SourceLocalPresenceFacts, caseName:String, rows:Array<ObservedUse>):Void {
        rows.push(row(caseName, "bodyExit", 0, "body", "available", "transferred", "Present", exitLabel(facts.exits)));
        var ambiguous = 0;
        for (diagnostic in facts.diagnostics)
            switch (diagnostic) {
                case AmbiguousNode: ambiguous += 1;
                case _:
            }
        rows.push(row(caseName, "ambiguousCount", 0, "body", "available", "transferred", "Present", Std.string(ambiguous)));
    }

    /**
        The abrupt-literal shape. No legal source expression puts a throw or a
        return inside an array literal, because the element type must unify,
        so this typed shape is built by hand here. It observes the assembly
        rule directly: the literal and its later sibling can deliver no
        produced value on a normal path.
    **/
    static function abruptLiteralRows(rows:Array<ObservedUse>):Void {
        final position = Context.currentPos();
        final text = Context.resolveType(macro :String, position);
        final thrown:haxe.macro.Type.TypedExpr = {
            expr: TThrow({expr: TConst(TString("no value")), t: text, pos: position}),
            t: text,
            pos: position
        };
        final sibling:haxe.macro.Type.TypedExpr = {expr: TConst(TString("d")), t: text, pos: position};
        final literal:haxe.macro.Type.TypedExpr = {
            expr: TArrayDecl([thrown, sibling]),
            t: Context.resolveType(macro :Array<String>, position),
            pos: position
        };
        final facts = SourceLocalPresenceAnalysis.prepare({
            body: literal,
            parameters: [],
            outerCapturedWrites: [],
            outerSummaryKind: SourceCaptureSummaryKind.EnclosingAssignsNothing,
            outerCaptureFacts: []
        });
        record(facts, "abruptLiteral", "use", literal, rows);
        record(facts, "abruptLiteral", "use", sibling, rows);
        recordCaseFacts(facts, "abruptLiteral", rows);
    }

    /**
        A typed AST directed acyclic graph that places one identical `TypedExpr`
        object at three reachable positions. Ordinary Haxe source that shares
        one physical node this way is not established, so this is
        identity-boundary assurance and not an authored source case: the
        ambiguity marker must stay sticky, so the third visit revives no record
        and the query keeps answering that the node has no occurrence.
    **/
    static function sharedNodeRows(rows:Array<ObservedUse>):Void {
        final position = Context.currentPos();
        final text = Context.resolveType(macro :Null<String>, position);
        final sharedLocal:TVar = {
            id: 900001,
            name: "shared",
            t: text,
            capture: false,
            extra: null,
            meta: null,
            isStatic: false
        };
        final shared:haxe.macro.Type.TypedExpr = {expr: TLocal(sharedLocal), t: text, pos: position};
        final statements:Array<haxe.macro.Type.TypedExpr> = [];
        for (index in 0...3) {
            final target:TVar = {
                id: 900010 + index,
                name: "target" + index,
                t: text,
                capture: false,
                extra: null,
                meta: null,
                isStatic: false
            };
            statements.push({expr: TVar(target, shared), t: text, pos: position});
        }
        final body:haxe.macro.Type.TypedExpr = {expr: TBlock(statements), t: text, pos: position};
        final facts = SourceLocalPresenceAnalysis.prepare({
            body: body,
            parameters: [],
            outerCapturedWrites: [],
            outerSummaryKind: SourceCaptureSummaryKind.EnclosingAssignsNothing,
            outerCaptureFacts: []
        });
        record(facts, "sharedNodeDag", "use", shared, rows);
        recordCaseFacts(facts, "sharedNodeDag", rows);
    }

    static function collect(facts:SourceLocalPresenceFacts, node:TypedExpr, name:String, rows:Array<ObservedUse>):Void {
        switch (node.expr) {
            case TFunction(fn):
                final child = facts.nestedAt(node);
                if (child != null)
                    collect(child, fn.expr, name + "#0", rows);
                return;
            case TCall(callee, args):
                if (isUseCall(callee) && args.length == 1)
                    record(facts, name, "use", args[0], rows);
            case TBinop(OpEq, l, r) | TBinop(OpNotEq, l, r):
                final subject = ExpressionPredicates.isNullExpr(l) ? r : (ExpressionPredicates.isNullExpr(r) ? l : null);
                if (subject != null)
                    switch (ExpressionPredicates.stripWrap(subject).expr) {
                        case TLocal(_): record(facts, name, "guardSubject", subject, rows);
                        case _:
                    }
            case _:
        }
        TypedExprTools.iter(node, function(child:TypedExpr):Void {
            collect(facts, child, name, rows);
        });
    }

    static function isUseCall(callee:TypedExpr):Bool {
        return switch (ExpressionPredicates.stripWrap(callee).expr) {
            case TField(_, FStatic(c, cf)): c.get().module == "lpc.Cases" && cf.get().name == "use";
            case _: false;
        }
    }

    static function record(facts:SourceLocalPresenceFacts, caseName:String, kind:String, subject:TypedExpr,
            rows:Array<ObservedUse>):Void {
        final observed = facts.useFacts(subject);
        rows.push(row(caseName, kind, countOf(rows, caseName, kind), switch (observed.subject) {
            case LocalUse(_): "local";
            case NonLocalUse: "nonLocal";
        }, switch (observed.availability) {
            case Available: "available";
            case UnreachablePath: "unreachable";
            case NoOccurrence: "noOccurrence";
            case NotReached(form): "notReached(" + form + ")";
        }, switch (observed.knowledge) {
            case Transferred: "transferred";
            case Conservative: "conservative";
        }, switch (observed.presence) {
            case Present(_): "Present";
            case Absent(_): "Absent";
            case Unknown: "Unknown";
        }, reasonLabel(observed.presence)));
    }

    static function row(caseName:String, kind:String, index:Int, subject:String, availability:String, knowledge:String, presence:String,
            reason:String):ObservedUse {
        return {
            caseName: caseName,
            kind: kind,
            index: index,
            subject: subject,
            availability: availability,
            knowledge: knowledge,
            presence: presence,
            reason: reason
        };
    }

    static function countOf(rows:Array<ObservedUse>, caseName:String, kind:String):Int {
        var count = 0;
        for (entry in rows)
            if (entry.caseName == caseName && entry.kind == kind)
                count += 1;
        return count;
    }

    /** The body exits that carry a reachable path, in a fixed order. */
    static function exitLabel(exits:Array<SourceBodyExit>):String {
        final labels:Array<String> = [];
        for (exit in exits) {
            final label = switch (exit) {
                case NormalExit(reachable, _): reachable ? "normal" : "";
                case ReturnExit(_, _): "return";
                case ThrowExit(_, _): "throw";
            };
            if (label.length > 0)
                labels.push(label);
        }
        labels.sort(Reflect.compare);
        return labels.length == 0 ? "none" : labels.join(",");
    }

    static function reasonLabel(presence:SourcePresence):String {
        return switch (presence) {
            case Present(reason) | Absent(reason): reasonLabelOf(reason);
            case Unknown: "NoReason";
        }
    }

    static function reasonLabelOf(reason:SourcePresenceReason):String {
        return switch (reason) {
            case ProducerContract(producer): "ProducerContract(" + producerLabel(producer) + ")";
            case GuardPresentOutcome(testedOperator): "GuardPresentOutcome(" + operatorLabel(testedOperator) + ")";
            case GuardAbsentOutcome(testedOperator): "GuardAbsentOutcome(" + operatorLabel(testedOperator) + ")";
            case NullAssignment: "NullAssignment";
            case NullLiteral: "NullLiteral";
            case JoinedPresent: "JoinedPresent";
            case JoinedAbsent: "JoinedAbsent";
            case NoReason: "NoReason";
        }
    }

    static function producerLabel(producer:SourceProducer):String {
        return switch (producer) {
            case SourceProducer.ScalarConstant: "ScalarConstant";
            case SourceProducer.ScalarOperation: "ScalarOperation";
            case SourceProducer.StringConcatenation: "StringConcatenation";
            case SourceProducer.CollectionConstruction: "CollectionConstruction";
            case SourceProducer.ObjectConstruction: "ObjectConstruction";
        }
    }

    static function operatorLabel(testedOperator:SourceGuardOperator):String {
        return testedOperator == SourceGuardOperator.NotEqualToNull ? "NotEqualToNull" : "EqualToNull";
    }
    #end

    // ------------------------------------------------------------------
    // Comparison
    // ------------------------------------------------------------------

    static function compare(rows:Array<ObservedUse>):Void {
        final taken:Array<Bool> = [for (index in 0...rows.length) false];
        for (expectation in EXPECTATIONS) {
            final matches = matching(rows, expectation);
            if (matches.length == 0) {
                failures.push("missing row " + expectationKey(expectation));
                continue;
            }
            if (matches.length > 1) {
                failures.push("duplicate row " + expectationKey(expectation));
                for (index in matches)
                    taken[index] = true;
                continue;
            }
            taken[matches[0]] = true;
            for (problem in differences(expectation, rows[matches[0]]))
                failures.push(expectationKey(expectation) + " " + problem);
        }
        for (index in 0...rows.length)
            if (!taken[index])
                failures.push("row with no expectation " + keyOf(rows[index]));
    }

    static function matching(rows:Array<ObservedUse>, expectation:ExpectedUse):Array<Int> {
        final out:Array<Int> = [];
        for (index in 0...rows.length) {
            final entry = rows[index];
            if (entry.caseName == expectation.caseName && entry.kind == expectation.kind && entry.index == expectation.index)
                out.push(index);
        }
        return out;
    }

    static function keyOf(row:ObservedUse):String {
        return row.caseName + ":" + row.kind + row.index;
    }

    static function expectationKey(expectation:ExpectedUse):String {
        return expectation.caseName + ":" + expectation.kind + expectation.index;
    }

    static function differences(expectation:ExpectedUse, row:ObservedUse):Array<String> {
        final out:Array<String> = [];
        if (row.subject != expectation.subject)
            out.push("subject " + row.subject + " expected " + expectation.subject);
        if (row.availability != expectation.availability)
            out.push("availability " + row.availability + " expected " + expectation.availability);
        if (row.knowledge != expectation.knowledge)
            out.push("knowledge " + row.knowledge + " expected " + expectation.knowledge);
        if (row.presence != expectation.presence)
            out.push("presence " + row.presence + " expected " + expectation.presence);
        if (row.reason != expectation.reason)
            out.push("reason " + row.reason + " expected " + expectation.reason);
        return out;
    }

    // ------------------------------------------------------------------
    // Authored expectations
    // ------------------------------------------------------------------

    static final LOCAL = "local";
    static final NON_LOCAL = "nonLocal";
    static final AVAILABLE = "available";
    static final TRANSFERRED = "transferred";

    static final present = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "NoReason");
    static final unknown = shape(LOCAL, AVAILABLE, TRANSFERRED, "Unknown", "NoReason");
    static final absentNull = shape(LOCAL, AVAILABLE, TRANSFERRED, "Absent", "NullLiteral");
    static final guardPresent = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "GuardPresentOutcome(NotEqualToNull)");
    static final guardAbsent = shape(LOCAL, AVAILABLE, TRANSFERRED, "Absent", "GuardAbsentOutcome(NotEqualToNull)");
    static final joinedPresent = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "JoinedPresent");
    static final constantShape = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(ScalarConstant)");
    static final operationShape = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(ScalarOperation)");
    static final concatShape = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(StringConcatenation)");
    static final collectionShape = shape(NON_LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(CollectionConstruction)");
    static final objectShape = shape(NON_LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(ObjectConstruction)");
    static final nonLocalUnknown = shape(NON_LOCAL, AVAILABLE, TRANSFERRED, "Unknown", "NoReason");
    static final unreachableRead = shape(LOCAL, "unreachable", "conservative", "Unknown", "NoReason");
    static final unreachableValueShape = shape(NON_LOCAL, "unreachable", "conservative", "Unknown", "NoReason");
    static final noOccurrenceShape = shape(LOCAL, "noOccurrence", "conservative", "Unknown", "NoReason");
    static final guardPresentEqualToNull = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "GuardPresentOutcome(EqualToNull)");
    static final absentEqualToNull = shape(LOCAL, AVAILABLE, TRANSFERRED, "Absent", "GuardAbsentOutcome(EqualToNull)");

    static final localCollection = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(CollectionConstruction)");
    static final localObject = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(ObjectConstruction)");
    static final localConcat = shape(LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(StringConcatenation)");
    static final nonLocalOperation = shape(NON_LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(ScalarOperation)");
    static final nonLocalConstant = shape(NON_LOCAL, AVAILABLE, TRANSFERRED, "Present", "ProducerContract(ScalarConstant)");

    static function shape(subject:String, availability:String, knowledge:String, presence:String,
            reason:String):{subject:String, availability:String, knowledge:String, presence:String, reason:String} {
        return {subject: subject, availability: availability, knowledge: knowledge, presence: presence, reason: reason};
    }

    static final ambiguityCases:Array<String> = [
        "skippableGuard", "loopGuardAfterLoop", "loopGuardSameIteration", "loopWriteAfterGuard", "callArgumentComparison",
        "assignmentAfterGuard", "joinedArms", "writingRightOperand", "captureWriteThroughCall", "fieldBehindPresentRoot",
        "tryRegionAssignment", "returnInsideGuard", "nestedOverMutableCapture", "nestedOverImmutableCapture", "producers",
        "explicitNullThroughAnnotation", "joinedPresentValues", "throwingArm", "unreachableTail", "postTestedLoop",
        "nestedWriteAbsent", "shortCircuitSkipsWrite", "orSkipsWrite", "guardedRightOperandRead", "literalAndGuardJoin",
        "indexedRead", "conditionCallThrow", "returnEdge", "loopTestSubject", "closureAfterWrite", "operandThrowKeepsNormal",
        "falseLeftSkipsRight", "trueLeftSkipsRight", "booleanValueJoin", "abruptLiteral", "returnOnlyTry", "booleanOrValueJoin",
        "assignmentKeepsRightEffects", "compoundAssignmentKeepsRightEffects",
    ];

    static function expectations():Array<ExpectedUse> {
        final base:Array<ExpectedUse> = [
        // C1 skippableGuard: a guard in a branch that can be skipped.
        at("skippableGuard", "guardSubject", 0, unknown),
        at("skippableGuard", "use", 0, guardPresent),
        at("skippableGuard", "use", 1, unknown),

        // C2 loopGuardAfterLoop
        at("loopGuardAfterLoop", "guardSubject", 0, unknown),
        at("loopGuardAfterLoop", "use", 0, guardPresent),
        at("loopGuardAfterLoop", "use", 1, unknown),

        // C3 loopGuardSameIteration
        at("loopGuardSameIteration", "guardSubject", 0, unknown),
        at("loopGuardSameIteration", "use", 0, joinedPresent),

        // C4 loopWriteAfterGuard
        at("loopWriteAfterGuard", "guardSubject", 0, unknown),
        at("loopWriteAfterGuard", "use", 0, guardPresent),
        at("loopWriteAfterGuard", "use", 1, unknown),

        // C5 callArgumentComparison
        at("callArgumentComparison", "guardSubject", 0, unknown),
        at("callArgumentComparison", "use", 0, unknown),

        // C6 assignmentAfterGuard
        at("assignmentAfterGuard", "guardSubject", 0, unknown),
        at("assignmentAfterGuard", "use", 0, guardPresent),
        at("assignmentAfterGuard", "use", 1, unknown),

        // C7 joinedArms
        at("joinedArms", "use", 0, constantShape),

        // C8 writingRightOperand
        at("writingRightOperand", "guardSubject", 0, unknown),
        at("writingRightOperand", "use", 0, guardPresent),
        at("writingRightOperand", "use", 1, constantShape),

        // C9 captureWriteThroughCall
        at("captureWriteThroughCall", "guardSubject", 0, unknown),
        at("captureWriteThroughCall", "use", 0, guardPresent),
        at("captureWriteThroughCall", "use", 1, unknown),

        // C10 fieldBehindPresentRoot
        at("fieldBehindPresentRoot", "guardSubject", 0, unknown),
        at("fieldBehindPresentRoot", "use", 0, nonLocalUnknown),

        // C11 tryRegionAssignment
        at("tryRegionAssignment", "use", 0, unknown),
        at("tryRegionAssignment", "use", 1, constantShape),
        at("tryRegionAssignment", "use", 2, unknown),

        // C12 returnInsideGuard
        at("returnInsideGuard", "guardSubject", 0, unknown),
        at("returnInsideGuard", "use", 0, guardPresent),
        at("returnInsideGuard", "use", 1, unknown),

        // C13 nestedOverMutableCapture
        at("nestedOverMutableCapture#0", "use", 0, unknown),
        at("nestedOverMutableCapture", "use", 0, constantShape),

        // C14 nestedOverImmutableCapture
        at("nestedOverImmutableCapture", "guardSubject", 0, unknown),
        at("nestedOverImmutableCapture#0", "use", 0, guardPresent),

        // C15 producers
        at("producers", "use", 0, localCollection),
        at("producers", "use", 1, localObject),
        at("producers", "use", 2, localConcat),
        at("producers", "use", 3, nonLocalOperation),
        at("producers", "use", 4, nonLocalUnknown),
        at("producers", "use", 5, nonLocalConstant),
        at("producers", "use", 6, nonLocalOperation),

        // C16 explicitNullThroughAnnotation
        at("explicitNullThroughAnnotation", "use", 0, absentNull),

        // C17 joinedPresentValues
        at("joinedPresentValues", "use", 0, {
            subject: NON_LOCAL,
            availability: AVAILABLE,
            knowledge: TRANSFERRED,
            presence: "Present",
            reason: "JoinedPresent"
        }),

        // C18 throwingArm
        at("throwingArm", "use", 0, constantShape),

        // C19 unreachableTail
        at("unreachableTail", "use", 0, unreachableRead),

        // C20 postTestedLoop
        at("postTestedLoop", "use", 0, unknown),
        at("postTestedLoop", "use", 1, unknown),

        // C21 nestedWriteAbsent: a nested write to null wins over a guard.
        at("nestedWriteAbsent", "guardSubject", 0, unknown),
        at("nestedWriteAbsent", "use", 0, absentNull),
        at("nestedWriteAbsent", "use", 1, absentNull),

        // C22 shortCircuitSkipsWrite
        at("shortCircuitSkipsWrite", "use", 0, unknown),

        // C23 orSkipsWrite
        at("orSkipsWrite", "use", 0, unknown),

        // C24 guardedRightOperandRead
        at("guardedRightOperandRead", "guardSubject", 0, unknown),
        at("guardedRightOperandRead", "use", 0, guardPresent),

        // C25 literalAndGuardJoin
        at("literalAndGuardJoin", "guardSubject", 0, unknown),
        at("literalAndGuardJoin", "use", 0, joinedPresent),

        // C26 indexedRead
        at("indexedRead", "use", 0, localCollection),
        at("indexedRead", "use", 1, nonLocalUnknown),

        // C27 conditionCallThrow
        at("conditionCallThrow", "use", 0, unknown),

        // C28 returnEdge
        at("returnEdge", "use", 0, unknown),

        // C29 loopTestSubject
        at("loopTestSubject", "guardSubject", 0, unknown),
        at("loopTestSubject", "use", 0, guardPresent),
        at("loopTestSubject", "use", 1, guardAbsent),

        // C30 closureAfterWrite
        at("closureAfterWrite", "guardSubject", 0, unknown),
        at("closureAfterWrite#0", "use", 0, unknown),
        at("closureAfterWrite", "use", 0, absentNull),

        // C32 falseLeftSkipsRight and C33 trueLeftSkipsRight: the right
        // operand never ran, so the write it names never happened.
        at("falseLeftSkipsRight", "use", 0, constantShape),
        at("trueLeftSkipsRight", "guardSubject", 0, unknown),
        at("trueLeftSkipsRight", "use", 0, guardPresent),

        // C34 booleanValueJoin: absent on the false outcome, present on the
        // true one, so the post-value read joins both.
        at("booleanValueJoin", "guardSubject", 0, unknown),
        at("booleanValueJoin", "guardSubject", 1, guardPresent),
        at("booleanValueJoin", "use", 0, unknown),

        // C35 abruptLiteral: neither the literal nor its later sibling can
        // yield a produced value on a normal path.
        at("abruptLiteral", "use", 0, unreachableValueShape),
        at("abruptLiteral", "use", 1, unreachableValueShape),

        // C36 returnOnlyTry: the catch never runs, so the read after the
        // region sits on no reachable path.
        at("returnOnlyTry", "use", 0, unreachableRead),

        // C37 sharedNodeDag: one physical node at three positions stays
        // answered as having no occurrence, with one ambiguity record.
        at("sharedNodeDag", "use", 0, noOccurrenceShape),

        // C38 booleanOrValueJoin: present on the false outcome, absent on the
        // true one, so the post-value read joins both.
        at("booleanOrValueJoin", "guardSubject", 0, unknown),
        at("booleanOrValueJoin", "guardSubject", 1, guardPresentEqualToNull),
        at("booleanOrValueJoin", "use", 0, unknown),

        // C39 assignmentKeepsRightEffects and C40
        // compoundAssignmentKeepsRightEffects: the destination write uses
        // the environment the right side left behind, so the compared read
        // right after the assignment cannot still see the captured local the
        // right side may null as present. The assignment target takes the
        // right side's own result.
        at("assignmentKeepsRightEffects", "guardSubject", 0, unknown),
        at("assignmentKeepsRightEffects", "use", 0, absentEqualToNull),
        at("assignmentKeepsRightEffects", "use", 1, unknown),
        at("compoundAssignmentKeepsRightEffects", "guardSubject", 0, unknown),
        at("compoundAssignmentKeepsRightEffects", "use", 0, absentEqualToNull),
        at("compoundAssignmentKeepsRightEffects", "use", 1, operationShape),

        // C31 operandThrowKeepsNormal
        at("operandThrowKeepsNormal", "use", 0, unknown),

        // Body exits. Every case's normal path is reachable unless a test
        // that cannot hold leaves it so; the listed additional exits come
        // from calls and returns in the case body.
        exit("skippableGuard", "normal,throw"),
        exit("loopGuardAfterLoop", "normal,throw"),
        exit("loopGuardSameIteration", "normal,throw"),
        exit("loopWriteAfterGuard", "normal,throw"),
        exit("callArgumentComparison", "normal,throw"),
        exit("assignmentAfterGuard", "normal,throw"),
        exit("joinedArms", "normal,throw"),
        exit("writingRightOperand", "normal,throw"),
        exit("captureWriteThroughCall", "normal,throw"),
        exit("fieldBehindPresentRoot", "normal,throw"),
        exit("tryRegionAssignment", "normal,throw"),
        exit("returnInsideGuard", "normal,return,throw"),
        exit("nestedOverMutableCapture", "normal,throw"),
        exit("nestedOverImmutableCapture", "normal,throw"),
        exit("producers", "normal,throw"),
        exit("explicitNullThroughAnnotation", "normal,throw"),
        exit("joinedPresentValues", "normal,throw"),
        exit("throwingArm", "normal,throw"),
        exit("unreachableTail", "return,throw"),
        exit("postTestedLoop", "normal,throw"),
        exit("nestedWriteAbsent", "normal,throw"),
        exit("shortCircuitSkipsWrite", "normal,throw"),
        exit("orSkipsWrite", "normal,throw"),
        exit("guardedRightOperandRead", "normal,throw"),
        exit("literalAndGuardJoin", "normal,throw"),
        exit("indexedRead", "normal,throw"),
        exit("conditionCallThrow", "normal,throw"),
        exit("returnEdge", "normal,return,throw"),
        exit("loopTestSubject", "normal,throw"),
        exit("closureAfterWrite", "normal,throw"),
        exit("operandThrowKeepsNormal", "normal,throw"),
        exit("falseLeftSkipsRight", "normal,throw"),
        exit("trueLeftSkipsRight", "normal,throw"),
        exit("booleanValueJoin", "normal,throw"),
        exit("abruptLiteral", "throw"),
        exit("returnOnlyTry", "return"),
        exit("booleanOrValueJoin", "normal,throw"),
        exit("sharedNodeDag", "normal"),
        exit("assignmentKeepsRightEffects", "normal,throw"),
        exit("compoundAssignmentKeepsRightEffects", "normal,throw"),
        // C37 sharedNodeDag holds exactly one stable ambiguity record.
        ambiguityFor("sharedNodeDag", 1),
        ];
        // No physical node may become ambiguous, including under the abstract
        // revisit of a loop test.
        return base.concat(ambiguity(0));
    }

    static final EXPECTATIONS:Array<ExpectedUse> = expectations();

    static function at(caseName:String, kind:String, index:Int,
            expectation:{subject:String, availability:String, knowledge:String, presence:String, reason:String}):ExpectedUse {
        return {
            caseName: caseName,
            kind: kind,
            index: index,
            subject: expectation.subject,
            availability: expectation.availability,
            knowledge: expectation.knowledge,
            presence: expectation.presence,
            reason: expectation.reason
        };
    }

    static function exit(caseName:String, reason:String):ExpectedUse {
        return {
            caseName: caseName,
            kind: "bodyExit",
            index: 0,
            subject: "body",
            availability: AVAILABLE,
            knowledge: TRANSFERRED,
            presence: "Present",
            reason: reason
        };
    }



    static function ambiguityFor(caseName:String, expected:Int):ExpectedUse {
        return {
            caseName: caseName,
            kind: "ambiguousCount",
            index: 0,
            subject: "body",
            availability: AVAILABLE,
            knowledge: TRANSFERRED,
            presence: "Present",
            reason: Std.string(expected)
        };
    }

    static function ambiguity(expected:Int):Array<ExpectedUse> {
        return [for (name in ambiguityCases) {
            caseName: name,
            kind: "ambiguousCount",
            index: 0,
            subject: "body",
            availability: AVAILABLE,
            knowledge: TRANSFERRED,
            presence: "Present",
            reason: Std.string(expected)
        }];
    }
}
