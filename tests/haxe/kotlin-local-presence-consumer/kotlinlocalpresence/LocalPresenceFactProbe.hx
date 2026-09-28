package kotlinlocalpresence;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import sys.FileSystem;
import sys.io.File;
import SourceLocalPresenceAnalysis;
import SourceLocalPresenceAnalysis.SourceLocalPresenceFacts;
import SourceLocalPresenceAnalysis.SourceUseFacts;
#end

/** Records source facts on the typed methods used by the Kotlin fixture. */
class LocalPresenceFactProbe {
    #if macro
    public static function run():Void {
        final lines:Array<String> = [];
        final cls = switch (Context.getType("kotlinlocalpresence.LocalPresenceOps")) {
            case TInst(ref, _): ref.get();
            case _: Context.error("LocalPresenceOps must be a class", Context.currentPos());
        }
        for (spec in [
            {method: "presentLocal", local: "local"},
            {method: "absentLocal", local: "local"},
            {method: "unknownOptional", local: "local"},
            {method: "unknownRequired", local: "local"},
            {method: "nestedLiteral", local: "value"},
            {method: "fusionLoopTrailing", local: "local"}
        ]) {
            final field = cls.statics.get().filter(member -> member.name == spec.method)[0];
            if (field == null || field.expr() == null)
                Context.error("missing typed body for " + spec.method, Context.currentPos());
            final typed = field.expr();
            final fn = switch (typed.expr) {
                case TFunction(value): value;
                case _: Context.error(spec.method + " is not a function", typed.pos);
            }
            final parameters = [for (argument in fn.args) {binding: argument.v.id, written: argument.v.t}];
            final facts = SourceLocalPresenceAnalysis.prepare({
                body: fn.expr,
                parameters: parameters,
                outerCapturedWrites: [],
                outerSummaryKind: SourceCaptureSummaryKind.EnclosingAssignsNothing,
                outerCaptureFacts: []
            });
            collectLocalReads(facts, fn.expr, spec.method, spec.local, lines);
        }
        probeUnavailableAndUnreachable(lines);
        FileSystem.createDirectory("out/kotlin-local-presence-consumer");
        File.saveContent("out/kotlin-local-presence-consumer/source-facts.tsv", lines.join("\n") + "\n");
        File.saveContent("out/kotlin-local-presence-consumer/production-use-facts.tsv", "");
        File.saveContent("out/kotlin-local-presence-consumer/prepared-root-facts.tsv", "");
    }

    static function collectLocalReads(facts:SourceLocalPresenceFacts, node:TypedExpr, method:String, name:String,
            lines:Array<String>):Void {
        switch (node.expr) {
            case TFunction(fn):
                final nested = facts.nestedAt(node);
                if (nested != null) {
                    recordOuterOccurrence(facts, nested, fn.expr, method, name, lines);
                    collectLocalReads(nested, fn.expr, method + "#nested", name, lines);
                }
                return;
            case TLocal(variable) if (variable.name == name):
                lines.push(method + "\t" + name + "\t" + label(facts.useFacts(node)));
            case _:
        }
        TypedExprTools.iter(node, child -> collectLocalReads(facts, child, method, name, lines));
    }

    /** The same nested use must have an occurrence only in its own body. */
    static function recordOuterOccurrence(outer:SourceLocalPresenceFacts, nested:SourceLocalPresenceFacts, node:TypedExpr,
            method:String, name:String, lines:Array<String>):Void {
        switch (node.expr) {
            case TLocal(variable) if (variable.name == name && nested.useFacts(node).occurrence != null):
                lines.push(method + "#outer	" + name + "	" + label(outer.useFacts(node)));
            case _:
        }
        TypedExprTools.iter(node, child -> recordOuterOccurrence(outer, nested, child, method, name, lines));
    }

    static function label(facts:SourceUseFacts):String {
        final subject = switch (facts.subject) {
            case LocalUse(binding): "LocalUse(" + binding + ")";
            case NonLocalUse: "NonLocalUse";
        }
        final availability = switch (facts.availability) {
            case Available: "Available";
            case UnreachablePath: "UnreachablePath";
            case NoOccurrence: "NoOccurrence";
            case NotReached(form): "NotReached(" + Std.string(form) + ")";
        }
        final knowledge = switch (facts.knowledge) {
            case Transferred: "Transferred";
            case Conservative: "Conservative";
        }
        final presence = switch (facts.presence) {
            case Present(_): "Present";
            case Absent(_): "Absent";
            case Unknown: "Unknown";
        }
        final occurrence = facts.occurrence == null ? "none" : Std.string(facts.occurrence.id);
        return subject + "\t" + availability + "\t" + knowledge + "\t" + presence + "\t" + occurrence;
    }

    static function probeUnavailableAndUnreachable(lines:Array<String>):Void {
        final position = Context.currentPos();
        final nullableText = Context.resolveType(macro :Null<String>, position);
        final stringType = Context.resolveType(macro :String, position);
        final binding:TVar = {
            id: 880001,
            name: "absentProbe",
            t: nullableText,
            capture: false,
            extra: null,
            meta: null,
            isStatic: false
        };
        final body:TypedExpr = {
            expr: TBlock([{expr: TVar(binding, {expr: TConst(TNull), t: nullableText, pos: position}), t: nullableText, pos: position}]),
            t: nullableText,
            pos: position
        };
        final prepared = SourceLocalPresenceAnalysis.prepare({
            body: body,
            parameters: [],
            outerCapturedWrites: [],
            outerSummaryKind: SourceCaptureSummaryKind.EnclosingAssignsNothing,
            outerCaptureFacts: []
        });
        final unavailable:TypedExpr = {expr: TLocal(binding), t: nullableText, pos: position};
        lines.push("unavailableLocal\tlocal\t" + label(prepared.useFacts(unavailable)));

        final thrown:TypedExpr = {
            expr: TThrow({expr: TConst(TString("stop")), t: stringType, pos: position}),
            t: stringType,
            pos: position
        };
        final later:TypedExpr = {expr: TConst(TString("later")), t: stringType, pos: position};
        final abrupt:TypedExpr = {
            expr: TArrayDecl([thrown, later]),
            t: Context.resolveType(macro :Array<String>, position),
            pos: position
        };
        final abruptFacts = SourceLocalPresenceAnalysis.prepare({
            body: abrupt,
            parameters: [],
            outerCapturedWrites: [],
            outerSummaryKind: SourceCaptureSummaryKind.EnclosingAssignsNothing,
            outerCaptureFacts: []
        });
        lines.push("unreachableNonLocal\tvalue\t" + label(abruptFacts.useFacts(later)));
    }
    #end
}
