package boring;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import DefaultArgExpander;
import swiftcompiler.SwiftArrayBoundary;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayOperation;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayOptionality;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayPresenceFact;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayStorage;
import swiftcompiler.SwiftParameterPlan;
#end

class SwiftBoundaryPlanChecks {
    #if macro
    public static macro function run():Expr {
        final mutableType = Context.typeof(macro ([] : Array<Int>));
        final readonlyType = Context.typeof(macro (null : std.ReadOnlyArray<Int>));
        final nullableReadonlyType = Context.typeof(macro (null : Null<std.ReadOnlyArray<Int>>));

        final operand:SwiftArrayPreparedOperand = {
            text: "values",
            sourceType: mutableType,
            storage: MutableArrayWrapper,
            optionality: RequiredOperand,
            presenceFact: SourceTypeRequired
        };
        final first = SwiftArrayBoundary.prepare(operand, readonlyType);
        final second = SwiftArrayBoundary.prepare(operand, readonlyType);
        if (first == null || second == null || first.operation != WrapMutableArrayView || second.operation != first.operation
            || first.resultStorage != ReadOnlyArrayView || second.resultStorage != first.resultStorage)
            throw new haxe.Exception("repeat preparation changed the mutable-to-read-only boundary decision");

        final unknownStorage:SwiftArrayPreparedOperand = {
            text: "other",
            sourceType: mutableType,
            storage: OtherArrayStorage,
            optionality: RequiredOperand,
            presenceFact: SourceTypeRequired
        };
        if (SwiftArrayBoundary.prepare(unknownStorage, readonlyType) != null)
            throw new haxe.Exception("unsupported prepared storage received an array boundary plan");
        final unknownOptional:SwiftArrayPreparedOperand = {
            text: "otherOptional",
            sourceType: Context.typeof(macro (null : Null<Array<Int>>)),
            storage: OtherArrayStorage,
            optionality: OptionalOperand,
            presenceFact: NoPresenceProof
        };
        if (SwiftArrayBoundary.prepare(unknownOptional, nullableReadonlyType) != null)
            throw new haxe.Exception("unsupported optional storage received an array boundary plan");

        final optionalView:SwiftArrayPreparedOperand = {
            text: "maybeView",
            sourceType: nullableReadonlyType,
            storage: ReadOnlyArrayView,
            optionality: OptionalOperand,
            presenceFact: NoPresenceProof
        };
        if (SwiftArrayBoundary.prepare(optionalView, readonlyType) != null)
            throw new haxe.Exception("optional prepared view was accepted as a required operand");

        final impossiblePresence:SwiftArrayPreparedOperand = {
            text: "nullableSource",
            sourceType: Context.typeof(macro (null : Null<Array<Int>>)),
            storage: MutableArrayWrapper,
            optionality: RequiredOperand,
            presenceFact: SourceTypeRequired
        };
        if (SwiftArrayBoundary.prepare(impossiblePresence, readonlyType) != null)
            throw new haxe.Exception("nullable source was accepted without a presence proof");
        if (SwiftArrayBoundary.prepare(impossiblePresence, nullableReadonlyType) != null)
            throw new haxe.Exception("optional destination repaired contradictory source presence facts");

        final optionalMutable:SwiftArrayPreparedOperand = {
            text: "maybeMutable",
            sourceType: Context.typeof(macro (null : Null<Array<Int>>)),
            storage: MutableArrayWrapper,
            optionality: OptionalOperand,
            presenceFact: NoPresenceProof
        };
        final optionalMap = SwiftArrayBoundary.prepare(optionalMutable, nullableReadonlyType);
        final optionalMapAgain = SwiftArrayBoundary.prepare(optionalMutable, nullableReadonlyType);
        if (optionalMap == null || optionalMapAgain == null || optionalMap.operation != MapOptionalMutableArrayView
            || optionalMap.resultStorage != ReadOnlyArrayView || optionalMap.resultOptionality != OptionalOperand
            || optionalMapAgain.operation != optionalMap.operation || optionalMapAgain.resultOptionality != optionalMap.resultOptionality)
            throw new haxe.Exception("optional mutable boundary preparation changed its decision");

        final operationsClass = switch (Context.getType("boring.ReadOnlyBoundaryOps")) {
            case TInst(classRef, _): classRef.get();
            case _: throw new haxe.Exception("nullable fallback fixture class did not resolve");
        };
        final nullableMethod = Lambda.find(operationsClass.statics.get(), field -> field.name == "nullableFallbackBoundary");
        if (nullableMethod == null)
            throw new haxe.Exception("nullable fallback fixture method did not resolve");
        final nullableArg = switch (Context.follow(nullableMethod.type)) {
            case TFun(args, _) if (args.length > 0): args[0];
            case _: throw new haxe.Exception("nullable fallback fixture parameter did not resolve");
        };
        final registered = DefaultArgExpander.defaultAt(operationsClass, nullableMethod.name, 0);
        if (registered == null || !DefaultArgExpander.isOptionalDefaultAt(operationsClass, nullableMethod.name, 0))
            throw new haxe.Exception("nullable fallback array parameter was not registered as optional");
        final coalescing = DefaultArgExpander.coalescingOf(registered);
        if (!DefaultArgExpander.coalescingCanBeNull(coalescing))
            throw new haxe.Exception("nullable fallback array fixture did not retain its null alternative");
        final nullablePlan = SwiftParameterPlan.forArgument(operationsClass, nullableMethod.name, nullableArg.name, 0, nullableArg.t);
        if (nullablePlan.bodyStorage != MutableArrayWrapper || nullablePlan.bodyOptionality != OptionalOperand
            || nullablePlan.bodyPresenceFact != NoPresenceProof || !SwiftArrayBoundary.isOptionalArrayType(nullablePlan.parameterType))
            throw new haxe.Exception("nullable array default plan invented a required body value");

        return macro null;
    }
    #end
}
