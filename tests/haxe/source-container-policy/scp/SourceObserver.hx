package scp;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import std.ReadOnlyArray;
import SourceContainerAnalysis;
import StaticFieldHelper;
#end

/**
    Observes the production container queries over the authored cases and
    over labelled synthetic handles.

    The macro reads the compiler-typed types of the declared cases in
    declaration order, before any other probe follows them, and emits one
    record per case. It never exits the compiler and never rejects source: a
    mismatching expectation is a runner decision, made later from authored
    expectations. Display strings in the records are evidence labels; no
    identity decision reads them.
**/
class SourceObserver {
    /** Builds the observed records of every authored and synthetic case. */
    public static macro function observeCases():ExprOf<Array<ObservedCase>> {
        final cls = switch (Context.getType("scp.SourceCases")) {
            case TInst(c, _):
                c.get();
            case other:
                Context.error("scp.SourceCases must be a class", Context.currentPos());
                null;
        }
        final records:Array<Expr> = [];
        for (field in cls.statics.get()) {
            records.push(record("authored", field.name, field.type, "macro-expansion-with-typed-class"));
        }
        final monomorph = Context.makeMonomorph();
        switch (monomorph) {
            case TMono(ref):
                if (ref.get() != null)
                    Context.error("new monomorph was already resolved", Context.currentPos());
            case _:
                Context.error("Context.makeMonomorph did not return TMono", Context.currentPos());
        }
        records.push(record("synthetic-mono-pending", "monoPending", monomorph, "before-Context.unify"));
        final arrayType = Context.resolveType(macro :Array<Int>, Context.currentPos());
        if (!Context.unify(monomorph, arrayType))
            Context.error("Context.unify did not resolve the monomorph", Context.currentPos());
        switch (monomorph) {
            case TMono(ref):
                if (ref.get() == null)
                    Context.error("monomorph remains pending after Context.unify", Context.currentPos());
            case _:
                Context.error("unified monomorph handle changed constructor", Context.currentPos());
        }
        records.push(record("synthetic-mono-resolved", "monoResolved", monomorph, "after-Context.unify"));
        for (synthetic in syntheticCases()) {
            records.push(record(synthetic.label, synthetic.name, synthetic.type, "synthetic-before-analysis"));
        }
        final readOnlyType = Context.resolveType(macro :std.ReadOnlyArray<String>, Context.currentPos());
        records.push(recordFirstAdapter("synthetic-adapter-first", "firstMutableQuery", TLazy(function() return readOnlyType), "isArrayType"));
        records.push(recordFirstAdapter("synthetic-adapter-first", "firstReadOnlyQuery", TLazy(function() return readOnlyType), "isReadOnlyArrayType"));
        records.push(recordFirstAdapter("synthetic-adapter-first", "firstElementQuery", TLazy(function() return readOnlyType), "arrayElementType"));
        final observed:Expr = {expr: EArrayDecl(records), pos: Context.currentPos()};
        return macro $observed;
    }

    #if macro
    /** Labelled synthetic handles; they are not accepted source forms. */
    static function syntheticCases():Array<{label:String, name:String, type:Null<Type>}> {
        final cases:Array<{label:String, name:String, type:Null<Type>}> = [];
        var selfReference:Null<Type> = null;
        final selfHandle:Void->Type = function() return selfReference;
        selfReference = TLazy(selfHandle);
        // The handle is resolved on demand through the supported macro API;
        // the underlying type is typed before the handle is built, so this
        // case exercises lazy resolution; type lookup happens before the
        // handle exists.
        final readOnlyType = Context.resolveType(macro :std.ReadOnlyArray<String>, Context.currentPos());
        cases.push({label: "synthetic-lazy", name: "lazyReadOnly", type: TLazy(function() return readOnlyType)});
        cases.push({label: "synthetic-lazy-failure", name: "lazyFailure", type: TLazy(function() throw "synthetic resolution failure")});
        cases.push({label: "synthetic-lazy-cycle", name: "lazyCycle", type: selfReference});
        cases.push({label: "synthetic-null", name: "nullInput", type: null});
        final nullType = Context.resolveType(macro :Null<Int>, Context.currentPos());
        final nullWithFailingInner = switch (nullType) {
            case TAbstract(abstractRef, _): TAbstract(abstractRef, [TLazy(function() throw "synthetic inner failure")]);
            case _: null;
        };
        if (nullWithFailingInner == null)
            Context.error("Null did not resolve to its typed abstract", Context.currentPos());
        cases.push({label: "synthetic-outer-null-lazy-failure", name: "outerNullLazyFailure", type: nullWithFailingInner});
        // A finite alias chain of twelve hops, authored in SourceCases and
        // resolved through the supported macro API.
        final chain = Context.resolveType(macro :scp.SourceCases.Chain01<Int>, Context.currentPos());
        cases.push({label: "synthetic-chain", name: "chainResolved", type: chain});
        return cases;
    }

    static function record(label:String, name:String, written:Null<Type>, phase:String):Expr {
        // The production adapters are the first observers of this input. The
        // canonical fact query follows them as an auxiliary observation.
        final mutable = StaticFieldHelper.isArrayType(written);
        final readOnly = StaticFieldHelper.isReadOnlyArrayType(written);
        final element = display(StaticFieldHelper.arrayElementType(written));
        return recordValues(label, name, written, phase, mutable, readOnly, element);
    }

    static function recordFirstAdapter(label:String, name:String, written:Type, first:String):Expr {
        var mutable = false;
        var readOnly = false;
        var element:Null<String> = null;
        switch (first) {
            case "isArrayType":
                mutable = StaticFieldHelper.isArrayType(written);
            case "isReadOnlyArrayType":
                readOnly = StaticFieldHelper.isReadOnlyArrayType(written);
            case "arrayElementType":
                element = display(StaticFieldHelper.arrayElementType(written));
            case _:
                Context.error("unknown first adapter", Context.currentPos());
        }
        if (first != "isArrayType")
            mutable = StaticFieldHelper.isArrayType(written);
        if (first != "isReadOnlyArrayType")
            readOnly = StaticFieldHelper.isReadOnlyArrayType(written);
        if (first != "arrayElementType")
            element = display(StaticFieldHelper.arrayElementType(written));
        return recordValues(label, name, written, "first-" + first, mutable, readOnly, element);
    }

    static function recordValues(label:String, name:String, written:Null<Type>, phase:String, mutable:Bool, readOnly:Bool, element:Null<String>):Expr {
        final facts = SourceContainerAnalysis.analyze(written);
        return macro {
            label: $v{label},
            name: $v{name},
            mutable: $v{mutable},
            readOnly: $v{readOnly},
            element: $v{element},
            phase: $v{phase},
            inputForm: $v{typeForm(written)},
            wrapper: $v{wrapperSpelling(facts.wrapper)},
            face: $v{faceSpelling(facts.face)},
            analyzedElement: $v{display(faceElement(facts.face))}
        };
    }

    static function typeForm(t:Null<Type>):String {
        return switch (t) {
            case null: "null";
            case TMono(_): "TMono";
            case TType(_, _): "TType";
            case TAbstract(_, _): "TAbstract";
            case TInst(_, _): "TInst";
            case TLazy(_): "TLazy";
            case _: "other-Type-variant";
        };
    }

    static function display(t:Null<Type>):Null<String> {
        return t == null ? null : TypeTools.toString(t);
    }

    static function faceElement(face:SourceContainerFace):Null<Type> {
        return switch (face) {
            case MutableArray(element): element;
            case ReadOnlyArrayFace(element): element;
            case _: null;
        };
    }

    static function wrapperSpelling(wrapper:SourceNullWrapper):String {
        return switch (wrapper) {
            case ExplicitOuterNull(wrapped):
                final shown = switch (wrapped) {
                    case TLazy(_): "TLazy";
                    case TMono(_): "TMono";
                    case _: display(wrapped);
                };
                "ExplicitOuterNull(" + shown + ")";
            case NoExplicitWrapper: "NoExplicitWrapper";
            case WrapperUnresolved(reason): "WrapperUnresolved(" + reasonSpelling(reason) + ")";
        };
    }

    static function faceSpelling(face:SourceContainerFace):String {
        return switch (face) {
            case MutableArray(element): "MutableArray(" + display(element) + ")";
            case ReadOnlyArrayFace(element): "ReadOnlyArrayFace(" + display(element) + ")";
            case OtherSourceType: "OtherSourceType";
            case UnresolvedSource(reason): "UnresolvedSource(" + reasonSpelling(reason) + ")";
        };
    }

    static function reasonSpelling(reason:UnresolvedReason):String {
        return switch (reason) {
            case NullTypeInput: "NullTypeInput";
            case LazyResolutionFailed: "LazyResolutionFailed";
            case PendingMonomorph: "PendingMonomorph";
            case CycleDetected: "CycleDetected";
        };
    }
    #end
}
