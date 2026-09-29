package dartcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceComparisonOperation;
import SourceComparisonAnalysis.SourceComparisonPlanResult;
import SourceComparisonAnalysis.SourceRecordComparisonPlan;

/** Dart callback requirements and concrete callback expressions for one
    finite source comparison graph. */
class DartComparisonPlan {
    /** Constructor ordering for record fields (stdlib/16), independent of payload equality.
        A switch evaluates its subject once and preserves sealed exhaustiveness. */
    public static function enumOrdinal(en:EnumType, operand:String, imports:DartImports, ?fields:Array<EnumField>):String {
        if (PolicyQueries.isValueEnum(en)) return operand + ".index";
        final constructors = fields == null ? [for (field in en.constructs) field] : fields.copy();
        constructors.sort((left, right) -> left.index - right.index);
        final arms = [for (field in constructors) {
            final name = DartDecl.constructClassName(en.name, field.name);
            final prefix = imports.type(en.module, name);
            (prefix.length > 0 ? prefix + "." : "") + name + "() => " + field.index;
        }];
        return "(switch (" + operand + ") { " + arms.join(", ") + " })";
    }

    public static function schema(cls:ClassType):Null<SourceRecordComparisonPlan> {
        return switch (SourceComparisonAnalysis.comparisonPlan(
                SourceComparisonAnalysis.analyzeRecordSchema(SourceComparisonAnalysis.declarationReference(cls)), SortedKey)) {
            case ComparisonPlanReady(plan): plan;
            case ComparisonPlanFailed(_, _, _): null;
            case ComparisonPlanUnresolved(path, reason):
                Context.error("Dart sorted comparator analysis incomplete at " + path + ": " + reason, cls.pos);
                null;
        };
    }

    /** Find demanded schema slots to a fixed point, including recursive edges.
        A nested record only propagates the slots its own plan actually reads. */
    public static function requiredArguments(root:SourceRecordComparisonPlan):Array<Int> {
        final records:Array<SourceRecordComparisonPlan> = [];
        function visit(record:SourceRecordComparisonPlan):Void {
            if (records.indexOf(record) >= 0) return;
            records.push(record);
            function nested(op:SourceComparisonOperation):Void switch (op) {
                case RecordOrder(child, _): visit(child);
                case NullBeforePresent(child) | Lexicographic(child): nested(child);
                case _:
            }
            for (field in record.fields) nested(field.operation);
        }
        visit(root);
        final demands:Array<Array<Int>> = [for (_ in records) []];
        function add(set:Array<Int>, index:Int):Bool {
            if (set.indexOf(index) >= 0) return false;
            set.push(index);
            return true;
        }
        function slots(type:Type, owner:SourceRecordComparisonPlan, found:Array<Int>):Void {
            final index = SourceComparisonAnalysis.ownParameterSlot(type, RecordDeclaration(owner.source.declarationRef));
            if (index != null) {
                add(found, index);
                return;
            }
            switch (type) {
                case TAbstract(_, args) | TInst(_, args) | TEnum(_, args) | TType(_, args):
                    for (arg in args) slots(arg, owner, found);
                case TLazy(resolve): slots(resolve(), owner, found);
                case _:
            }
        }
        var changed = true;
        while (changed) {
            changed = false;
            for (recordIndex in 0...records.length) {
                final record = records[recordIndex];
                final demanded = demands[recordIndex];
                function collect(op:SourceComparisonOperation):Void switch (op) {
                    case ParameterOrder(index):
                        if (add(demanded, index)) changed = true;
                    case RecordOrder(child, args):
                        final childDemands = demands[records.indexOf(child)];
                        for (childIndex in childDemands) if (childIndex < args.length) {
                            final found:Array<Int> = [];
                            slots(args[childIndex], record, found);
                            for (index in found) if (add(demanded, index)) changed = true;
                        }
                    case NullBeforePresent(child) | Lexicographic(child): collect(child);
                    case _:
                }
                for (field in record.fields) collect(field.operation);
            }
        }
        final result = demands[records.indexOf(root)];
        result.sort((left, right) -> left - right);
        return result;
    }

    /** Render an argument callback for a concrete or symbolic source type.
        Symbolic parameters resolve against the owning record's callback
        parameters. All other operations follow the source plan's admitted
        container and record shapes. */
    public static function comparatorForType(type:Type, imports:DartImports, ?owner:SourceRecordComparisonPlan):String {
        if (owner != null) {
            final slot = SourceComparisonAnalysis.ownParameterSlot(type, RecordDeclaration(owner.source.declarationRef));
            if (slot != null) return "compareArg" + slot;
        }
        return switch (type) {
            case TAbstract(reference, args) if (reference.get().name == "Null" && args.length == 1):
                final child = comparatorForType(args[0], imports, owner);
                "(left, right) { if (left == null) return right == null ? 0 : -1; if (right == null) return 1; return " + child + "(left, right); }";
            case TAbstract(reference, args) if (reference.get().name == "ReadOnlyArray"
                    && reference.get().pack.join(".") == "std" && args.length == 1):
                final child = comparatorForType(args[0], imports, owner);
                "(left, right) { for (var index = 0; index < left.length && index < right.length; index++) { final order = "
                    + child + "(left[index], right[index]); if (order != 0) return order; } return left.length.compareTo(right.length); }";
            case TAbstract(reference, _) if (reference.get().name == "Int"):
                "(left, right) => left.compareTo(right)";
            case TInst(reference, args) if (reference.get().name == "String"):
                "(left, right) => left.compareTo(right)";
            case TEnum(reference, _):
                "(left, right) => " + enumOrdinal(reference.get(), "left", imports)
                    + ".compareTo(" + enumOrdinal(reference.get(), "right", imports) + ")";
            case TInst(reference, args) if (reference.get().meta.has(":dataClass")):
                final cls = reference.get();
                final plan = schema(cls);
                if (plan == null) {
                    Context.error("Dart key callback has no source ordering plan for " + cls.name, cls.pos);
                    "";
                } else {
                    final prefix = imports.value(cls.module, "compare" + cls.name);
                    final name = (prefix.length > 0 ? prefix + "." : "") + "compare" + cls.name;
                    final callbacks = [for (index in requiredArguments(plan)) comparatorForType(args[index], imports, owner)];
                    if (callbacks.length == 0) name
                    else "(left, right) => " + name + "(left, right, " + callbacks.join(", ") + ")";
                }
            case TLazy(resolve):
                comparatorForType(resolve(), imports, owner);
            case TType(_, _):
                comparatorForType(Context.follow(type), imports, owner);
            case _:
                Context.error("Dart key callback has no target operation for " + Std.string(type), Context.currentPos());
                "";
        };
    }
}
#end
