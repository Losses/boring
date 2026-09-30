package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import StaticFieldHelper;

/** Swift storage representation already produced for an operand. */
enum SwiftArrayStorage {
    MutableArrayWrapper;
    ReadOnlyArrayView;
    ContextualEmptyLiteral;
    NullArrayValue;
    OtherArrayStorage;
}

/** Optionality of the prepared Swift operand after applicable flow facts. */
enum SwiftArrayOptionality {
    RequiredOperand;
    OptionalOperand;
}

/** Why a nullable source is currently represented by a required value. */
enum SwiftArrayPresenceFact {
    SourceTypeRequired;
    LiteralProvenPresent;
    GuardProvenPresent;
    BranchValuesRequired;
    DefaultMaterializedPresent;
    NoPresenceProof;
}

/** Target operation selected for one boundary. */
enum SwiftArrayOperation {
    KeepPreparedArray;
    PreserveNullArrayValue;
    WrapMutableArrayView;
    MapOptionalMutableArrayView;
    ContextualReadOnlyEmpty;
    CopyReadOnlyIntoMutableArray;
    MapOptionalReadOnlyIntoMutableArray;
}

/** One expression lowering's text and the representation facts it established. */
typedef SwiftArrayPreparedOperand = {
    final text:String;
    final sourceType:Null<Type>;
    final storage:SwiftArrayStorage;
    final optionality:SwiftArrayOptionality;
    final presenceFact:SwiftArrayPresenceFact;
}

/** Immutable result of preparing a typed source-to-destination boundary. */
typedef SwiftArrayBoundaryPlan = {
    final sourceType:Null<Type>;
    final destinationType:Null<Type>;
    final sourceStorage:SwiftArrayStorage;
    final sourceOptionality:SwiftArrayOptionality;
    final presenceFact:SwiftArrayPresenceFact;
    final destinationOptional:Bool;
    final resultStorage:SwiftArrayStorage;
    final resultOptionality:SwiftArrayOptionality;
    final elementType:Null<Type>;
    final operation:SwiftArrayOperation;
}

/**
    Swift-local storage and conversion decisions for Haxe array boundaries.
    The producer receives AST provenance, the storage representation
    established by operand preparation, and flow-derived optionality. It
    never prints or reads emitted text. Rendering consumes this immutable
    plan plus the operand string from the same preparation environment.
**/
class SwiftArrayBoundary {
    static function withoutNull(t:Null<Type>):Null<Type> {
        if (t == null)
            return null;
        return switch (Context.follow(t)) {
            case TAbstract(a, [inner]) if (a.get().name == "Null"): withoutNull(inner);
            case _: t;
        };
    }

    static function isMutableArray(t:Null<Type>):Bool {
        return switch (Context.follow(withoutNull(t))) {
            case TInst(c, _): c.get().pack.length == 0 && c.get().name == "Array";
            case TAbstract(a, _): a.get().name == "Array";
            case _: false;
        };
    }

    static function isReadOnlyArray(t:Null<Type>):Bool
        return StaticFieldHelper.isReadOnlyArrayType(t);

    static function isOptionalType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        switch (t) {
            case TAbstract(a, _) if (a.get().name == "Null"):
                return true;
            case _:
        }
        return switch (Context.follow(t)) {
            case TAbstract(a, _) if (a.get().name == "Null"): true;
            case _: false;
        };
    }

    public static function isOptionalArrayType(t:Null<Type>):Bool
        return isOptionalType(t);

    static function elementType(t:Null<Type>):Null<Type> {
        if (t == null)
            return null;
        switch (t) {
            case TAbstract(a, [inner]) if (a.get().name == "Null"):
                return elementType(inner);
            case _:
        }
        final unwrapped = withoutNull(t);
        final direct = switch (unwrapped) {
            case TInst(c, params) if (c.get().name == "Array" && params.length > 0): params[0];
            case TAbstract(a, params) if ((a.get().name == "ReadOnlyArray" || a.get().module == "std.ReadOnlyArray")
                && params.length > 0): params[0];
            case TType(d, params) if ((d.get().name == "ReadOnlyArray" || d.get().module == "std.ReadOnlyArray")
                && params.length > 0): params[0];
            case TLazy(f): return elementType(f());
            case _: null;
        };
        if (direct != null)
            return direct;
        return switch (Context.follow(unwrapped)) {
            case TInst(c, params) if (c.get().name == "Array" && params.length > 0): params[0];
            case TAbstract(a, params) if ((a.get().name == "ReadOnlyArray" || a.get().module == "std.ReadOnlyArray")
                && params.length > 0): params[0];
            case TType(d, params) if ((d.get().name == "ReadOnlyArray" || d.get().module == "std.ReadOnlyArray")
                && params.length > 0): params[0];
            case TLazy(f): elementType(f());
            case _: null;
        };
    }

    /** Distinguish a container boundary from an ordinary assignment. */
    public static function isBoundary(sourceType:Null<Type>, destinationType:Null<Type>):Bool
        return isReadOnlyArray(destinationType) || (isMutableArray(destinationType) && isReadOnlyArray(sourceType));

    /** Classify source syntax; it does not replace a prepared storage fact. */
    public static function sourceStorage(t:Null<Type>, emptyLiteral:Bool = false, nullLiteral:Bool = false):SwiftArrayStorage {
        if (nullLiteral)
            return NullArrayValue;
        if (emptyLiteral)
            return ContextualEmptyLiteral;
        if (isReadOnlyArray(t))
            return ReadOnlyArrayView;
        if (isMutableArray(t))
            return MutableArrayWrapper;
        return OtherArrayStorage;
    }

    /**
        Prepare a boundary from actual emitted representation and flow state.
        Source and destination Types preserve Haxe type evidence; they never
        override preparedStorage or preparedOptionality.
    **/
    public static function prepare(operand:SwiftArrayPreparedOperand, destinationType:Null<Type>,
            destinationOptionalOverride:Null<Bool> = null):Null<SwiftArrayBoundaryPlan> {
        final sourceType = operand.sourceType;
        final preparedStorage = operand.storage;
        final preparedOptionality = operand.optionality;
        final presenceFact = operand.presenceFact;
        final destReadOnly = isReadOnlyArray(destinationType);
        final destMutable = isMutableArray(destinationType);
        final destOptional = destinationOptionalOverride == null ? isOptionalType(destinationType) : destinationOptionalOverride;
        var operation:Null<SwiftArrayOperation> = null;
        var resultStorage = preparedStorage;
        var resultOptionality = preparedOptionality;
        final element = destReadOnly ? elementType(destinationType) : elementType(sourceType);

        if (destReadOnly) {
            switch (preparedStorage) {
                case ContextualEmptyLiteral:
                    if (element != null) {
                        operation = ContextualReadOnlyEmpty;
                        resultStorage = ReadOnlyArrayView;
                        resultOptionality = RequiredOperand;
                    }
                case NullArrayValue:
                    if (destOptional) {
                        operation = PreserveNullArrayValue;
                        resultStorage = NullArrayValue;
                        resultOptionality = OptionalOperand;
                    }
                case MutableArrayWrapper:
                    if (element != null) {
                        resultStorage = ReadOnlyArrayView;
                        switch (preparedOptionality) {
                            case RequiredOperand:
                                operation = WrapMutableArrayView;
                                resultOptionality = RequiredOperand;
                            case OptionalOperand if (destOptional):
                                operation = MapOptionalMutableArrayView;
                                resultOptionality = OptionalOperand;
                            case OptionalOperand:
                        }
                    }
                case ReadOnlyArrayView:
                    if (preparedOptionality == RequiredOperand || destOptional) {
                        operation = KeepPreparedArray;
                    }
                case OtherArrayStorage:
            }
        } else if (destMutable && preparedStorage == ReadOnlyArrayView && element != null) {
            resultStorage = MutableArrayWrapper;
            switch (preparedOptionality) {
                case RequiredOperand:
                    operation = CopyReadOnlyIntoMutableArray;
                    resultOptionality = RequiredOperand;
                case OptionalOperand if (destOptional):
                    operation = MapOptionalReadOnlyIntoMutableArray;
                    resultOptionality = OptionalOperand;
                case OptionalOperand:
            }
        }

        if (isOptionalType(sourceType)
            && preparedOptionality == RequiredOperand
            && presenceFact != LiteralProvenPresent
            && presenceFact != GuardProvenPresent
            && presenceFact != BranchValuesRequired
            && presenceFact != DefaultMaterializedPresent)
            operation = null;

        if (operation == null)
            return null;

        return {
            sourceType: sourceType,
            destinationType: destinationType,
            sourceStorage: preparedStorage,
            sourceOptionality: preparedOptionality,
            presenceFact: presenceFact,
            destinationOptional: destOptional,
            resultStorage: resultStorage,
            resultOptionality: resultOptionality,
            elementType: element,
            operation: operation
        };
    }

    /** Render a plan. The text is an already-lowered operand, never a query input. */
    public static function render(plan:SwiftArrayBoundaryPlan, operand:String, elementText:Null<String>):String {
        return switch (plan.operation) {
            case KeepPreparedArray | PreserveNullArrayValue: operand;
            case WrapMutableArrayView: "ReadOnlyArray(" + operand + ")";
            case MapOptionalMutableArrayView: "(" + operand + ").map { ReadOnlyArray($0) }";
            case ContextualReadOnlyEmpty:
                elementText == null ?throw new haxe.Exception("read-only empty array boundary is missing its element type"):"ReadOnlyArray<" + elementText +
                ">()";
            case CopyReadOnlyIntoMutableArray: operand + ".toMutableArray()";
            case MapOptionalReadOnlyIntoMutableArray: "(" + operand + ").map { $0.toMutableArray() }";
        };
    }
}
#end
