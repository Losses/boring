package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceComparisonOperation;
import SourceComparisonAnalysis.SourceComparisonRequest;
import SourceComparisonAnalysis.SourceAdmissionResult;
import SourceComparisonAnalysis.SourceOperationResult;
import SourceComparisonAnalysis.SourceRecordComparisonPlan;

/** Kotlin expressions for the operations selected by source comparison facts. */
class KotlinComparisonPlan {
    final imports:KotlinImports;

    public function new(imports:KotlinImports) {
        this.imports = imports;
    }

    public function requiredSlots(declaration:Ref<ClassType>, arguments:Array<Type>):Array<Int> {
        return switch (SourceComparisonAnalysis.admit(declaration, arguments, SortedKey)) {
            case SourceAdmissionAdmitted(summary): summary.requiredSlots;
            case SourceAdmissionRejected(reason, site, _):
                Context.error("Kotlin comparison rejected at " + site.field + ": " + reason, Context.currentPos());
                [];
            case SourceAdmissionIncomplete(reason, site, _):
                Context.error("Kotlin comparison incomplete at " + site.field + ": " + reason, Context.currentPos());
                [];
        };
    }

    public function argumentComparator(type:Type, ?owner:SourceRecordComparisonPlan):String {
        if (owner != null) {
            final index = SourceComparisonAnalysis.schemaParameterIndex(type, owner.source.arguments);
            if (index != null)
                return "compareParam" + index;
        }
        final operation = switch (SourceComparisonAnalysis.operationForType(type, SortedKey)) {
            case OperationReady(selected): selected;
            case OperationFailed(reason, _):
                Context.error("Kotlin comparison argument rejected: " + reason, Context.currentPos());
                null;
            case OperationUnresolved(reason):
                Context.error("Kotlin comparison argument incomplete: " + reason, Context.currentPos());
                null;
        };
        return "{ left, right -> " + render(operation, "left", "right", owner) + " }";
    }

    public function render(operation:SourceComparisonOperation, left:String, right:String,
            ?owner:SourceRecordComparisonPlan, depth:Int = 0):String {
        return switch (operation) {
            case IntegerOrder | Utf16StringOrder:
                '$left.compareTo($right)';
            case ParameterOrder(index):
                'compareParam$index($left, $right)';
            case EnumOrdinalOrder(declaration, _, constructors):
                final name = declaration.name;
                imports.requireType(declaration.module, name);
                function ordinal(value:String):String {
                    final arms = [
                        for (constructor in constructors)
                            (switch (constructor.type) {
                                case TFun(args, _) if (args.length > 0): 'is $name.${constructor.name}';
                                case _: '$name.${constructor.name}';
                            }) + ' -> ${constructor.index}'
                    ];
                    return 'when ($value) { ${arms.join("; ")} }';
                }
                '${ordinal(left)}.compareTo(${ordinal(right)})';
            case RecordOrder(record, arguments):
                final nested = record.source.declaration;
                final qualifier = nested.pack.length == 0 ? "" : nested.pack.join(".") + ".";
                final passed = [
                    for (slot in requiredSlots(record.source.declarationRef, record.source.arguments))
                        argumentComparator(arguments[slot], owner)
                ];
                final suffix = passed.length == 0 ? "" : ", " + passed.join(", ");
                '${qualifier}compare${nested.name}($left, $right$suffix)';
            case NullBeforePresent(child):
                final a = "nullableLeft" + depth;
                final b = "nullableRight" + depth;
                final compared = render(child, a, b, owner, depth + 1);
                'run { val $a = $left; val $b = $right; when { $a == null && $b == null -> 0; $a == null -> -1; $b == null -> 1; else -> $compared } }';
            case Lexicographic(child):
                final a = "sequenceLeft" + depth;
                final b = "sequenceRight" + depth;
                final index = "index" + depth;
                final difference = "difference" + depth;
                final compared = render(child, a + "[" + index + "]", b + "[" + index + "]", owner, depth + 1);
                'run { val $a = $left; val $b = $right; var $index = 0; var $difference = 0; while ($index < $a.size && $index < $b.size) { $difference = $compared; if ($difference != 0) break; $index += 1 }; if ($difference != 0) $difference else $a.size.compareTo($b.size) }';
            case FloatOrder | BooleanOrder:
                Context.error("Kotlin sorted comparator received an equality-only source operation", Context.currentPos());
                "0";
        };
    }
}
#end
