package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import SourceComparisonAnalysis;

/** Target realization of a completed, target-independent source comparison
    operation graph. Names and runtime dependencies are assigned here. This
    replaces Swift's former ComparatorPlan.entries consumer. */
class SwiftComparisonPlan {
    public static function select(declaration:Ref<ClassType>, arguments:Array<Type>, request:SourceComparisonRequest):SwiftComparisonPlanResult {
        final source = SourceComparisonAnalysis.analyzeRecord(declaration, arguments);
        return switch (SourceComparisonAnalysis.comparisonPlan(source, request)) {
            case ComparisonPlanFailed(path, reason, sourceType): SwiftComparisonPlanFailed(path, reason, sourceType);
            case ComparisonPlanUnresolved(path, reason): SwiftComparisonPlanUnresolved(path, reason);
            case ComparisonPlanReady(plan): new SwiftPlanBuilder().realize(plan, "");
        };
    }

    public static function selectSchema(declaration:Ref<ClassType>, request:SourceComparisonRequest):SwiftComparisonPlanResult {
        return switch (SourceComparisonAnalysis.comparisonPlan(SourceComparisonAnalysis.analyzeRecordSchema(declaration), request)) {
            case ComparisonPlanFailed(path, reason, sourceType): SwiftComparisonPlanFailed(path, reason, sourceType);
            case ComparisonPlanUnresolved(path, reason): SwiftComparisonPlanUnresolved(path, reason);
            case ComparisonPlanReady(plan): new SwiftPlanBuilder().realize(plan, "");
        };
    }
}

private class SwiftPlanBuilder {
    final records:Array<{source:SourceRecordComparisonPlan, realization:SwiftRecordPlan}> = [];

    public function new() {}

    public function realize(source:SourceRecordComparisonPlan, path:String):SwiftComparisonPlanResult {
        for (entry in records)
            if (entry.source == source)
                return SwiftComparisonPlanReady(entry.realization);

        final realization = new SwiftRecordPlan(source, recordName(source.source.declaration));
        records.push({source: source, realization: realization});
        for (field in source.fields) {
            final fieldPath = path == "" ? field.field.name : path + "_" + field.field.name;
            switch (operation(field.operation, fieldPath, realization)) {
                case SwiftOperationReady(selected): realization.fields.push({field: field.field, operation: selected});
                case SwiftOperationFailed(reason, sourceType): return SwiftComparisonPlanFailed(fieldPath, reason, sourceType);
                case SwiftOperationUnresolved(reason): return SwiftComparisonPlanUnresolved(fieldPath, reason);
            }
        }
        realization.requiredArguments = requiredArguments(realization);
        realization.complete = true;
        return SwiftComparisonPlanReady(realization);
    }

    function requiredArguments(plan:SwiftRecordPlan):Array<Int> {
        final result:Array<Int> = [];
        function add(index:Int):Void if (result.indexOf(index) < 0) result.push(index);
        function collect(operation:SwiftComparisonOperation):Void {
            switch (operation) {
                case SwiftParameterOrder(index): add(index);
                case SwiftRecordOrder(nested, arguments):
                    for (nestedIndex in nested.requiredArguments) {
                        if (nestedIndex < arguments.length) {
                            final parentIndex = SourceComparisonAnalysis.schemaParameterIndex(arguments[nestedIndex], plan.source.source.arguments);
                            if (parentIndex != null) add(parentIndex);
                        }
                    }
                case SwiftNullBeforePresent(child) | SwiftLexicographic(child): collect(child);
                case _:
            }
        }
        for (field in plan.fields) collect(field.operation);
        result.sort((left, right) -> left - right);
        return result;
    }

    function operation(source:SourceComparisonOperation, path:String, owner:SwiftRecordPlan):SwiftOperationResult {
        return switch (source) {
            case IntegerOrder: SwiftOperationReady(SwiftIntegerOrder);
            case Utf16StringOrder:
                addDependency(owner, "compareUnitOrder");
                SwiftOperationReady(SwiftUtf16StringOrder);
            case FloatOrder: SwiftOperationReady(SwiftFloatOrder);
            case BooleanOrder: SwiftOperationReady(SwiftBooleanOrder);
            case ParameterOrder(index): SwiftOperationReady(SwiftParameterOrder(index));
            case EnumOrdinalOrder(declaration, arguments, constructors):
                // These helpers print at file scope; give each record plan
                // its own prefix so sibling plans in one source module cannot
                // redeclare enumOrder0. The source identity remains the enum
                // declaration below, independently of this target symbol.
                final name = owner.name + "_enumOrder" + owner.enumHelpers.length;
                owner.enumHelpers.push({name: name, declaration: declaration, arguments: arguments.copy(), constructors: constructors.copy()});
                SwiftOperationReady(SwiftEnumOrdinalOrder(name, declaration, arguments.copy()));
            case RecordOrder(record, arguments):
                switch (realize(record, path)) {
                    case SwiftComparisonPlanReady(nested): SwiftOperationReady(SwiftRecordOrder(nested, arguments.copy()));
                    case SwiftComparisonPlanFailed(failedPath, reason, sourceType): SwiftOperationFailed(failedPath + ": " + reason, sourceType);
                    case SwiftComparisonPlanUnresolved(failedPath, reason): SwiftOperationUnresolved(failedPath + ": " + reason);
                }
            case NullBeforePresent(child):
                switch (operation(child, path, owner)) {
                    case SwiftOperationReady(selected): SwiftOperationReady(SwiftNullBeforePresent(selected));
                    case SwiftOperationFailed(reason, sourceType): SwiftOperationFailed(reason, sourceType);
                    case SwiftOperationUnresolved(reason): SwiftOperationUnresolved(reason);
                }
            case Lexicographic(child):
                addDependency(owner, "ReadOnlyArray");
                switch (operation(child, path + "_element", owner)) {
                    case SwiftOperationReady(selected): SwiftOperationReady(SwiftLexicographic(selected));
                    case SwiftOperationFailed(reason, sourceType): SwiftOperationFailed(reason, sourceType);
                    case SwiftOperationUnresolved(reason): SwiftOperationUnresolved(reason);
                }
        };
    }

    function addDependency(owner:SwiftRecordPlan, name:String):Void {
        if (owner.dependencies.indexOf(name) < 0)
            owner.dependencies.push(name);
    }

    static function recordName(declaration:ClassType):String {
        // Swift emits private classes at file scope. Distinct source modules
        // can therefore each declare the same short class name in one Swift
        // compilation. Encode the full declaration path so their file-scope
        // comparator and enum helper names remain distinct.
        final segments = (declaration.module + "." + declaration.name).split(".");
        return "compareRecord_" + [for (segment in segments) segment.length + "_" + segment].join("_");
    }

}

enum SwiftComparisonPlanResult {
    SwiftComparisonPlanReady(plan:SwiftRecordPlan);
    SwiftComparisonPlanFailed(path:String, reason:String, sourceType:Null<Type>);
    SwiftComparisonPlanUnresolved(path:String, reason:String);
}

enum SwiftOperationResult {
    SwiftOperationReady(operation:SwiftComparisonOperation);
    SwiftOperationFailed(reason:String, sourceType:Null<Type>);
    SwiftOperationUnresolved(reason:String);
}

class SwiftRecordPlan {
    public final source:SourceRecordComparisonPlan;
    public final name:String;
    public final fields:Array<SwiftPlannedField> = [];
    public var enumHelpers:Array<SwiftEnumOrderHelper> = [];
    public var dependencies:Array<String> = [];
    public var complete:Bool = false;
    public var requiredArguments:Array<Int> = [];

    public function new(source:SourceRecordComparisonPlan, name:String) {
        this.source = source;
        this.name = name;
    }
}

typedef SwiftPlannedField = {
    final field:ClassField;
    final operation:SwiftComparisonOperation;
}

typedef SwiftEnumOrderHelper = {
    final name:String;
    final declaration:EnumType;
    final arguments:Array<Type>;
    final constructors:Array<EnumField>;
}

enum SwiftComparisonOperation {
    SwiftIntegerOrder;
    SwiftUtf16StringOrder;
    SwiftFloatOrder;
    SwiftBooleanOrder;
    SwiftEnumOrdinalOrder(helper:String, declaration:EnumType, arguments:Array<Type>);
    SwiftParameterOrder(index:Int);
    SwiftRecordOrder(record:SwiftRecordPlan, arguments:Array<Type>);
    SwiftNullBeforePresent(child:SwiftComparisonOperation);
    SwiftLexicographic(child:SwiftComparisonOperation);
}
#end
