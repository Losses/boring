package;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import ValueTypeSupport.ValueTypeOperator;

/** Shared decision record for synthetic value-type lowering. */
typedef ValueTypeQueries = {
    var markedAbstractOfType:Null<Type>->Null<AbstractType>;
    var localValues:TypedExpr->Map<Int, TypedExpr>;
    var activeAbstract:Void->Null<AbstractType>;
    var activeField:AbstractType->Null<String>->Null<ClassField>;
    var activeFieldName:Void->Null<String>;
    var stripValue:TypedExpr->TypedExpr;
    var wrapNative:Bool;
};

enum ValueTypePlanKind {
    ValueTypeFallback;
    ValueTypeBinary(op:Binop, left:TypedExpr, right:TypedExpr);
    ValueTypeUnary(op:Unop, subject:TypedExpr);
}

/**
    Resolves the target-independent part of a synthetic value-type operation.
    Rendering, imports, and representation/ownership conversions remain in
    each target emitter.
**/
class ValueTypePlan {
    public var abstractType:Null<AbstractType>;
    public var locals:Map<Int, TypedExpr>;
    public var kind:ValueTypePlanKind;
    public var field:Null<ClassField>;
    public var nativeOperator:Bool;
    public var wrapperRequired:Bool;

    public static function planValueTypeSynthetic(wrapper:TypedExpr, value:TypedExpr,
            queries:ValueTypeQueries):ValueTypePlan {
        final result = new ValueTypePlan();
        result.locals = queries.localValues(wrapper);
        result.kind = ValueTypeFallback;
        result.field = null;
        result.nativeOperator = false;
        result.wrapperRequired = false;
        final abs = queries.markedAbstractOfType(wrapper.t);
        if (abs == null) {
            result.abstractType = null;
            return result;
        }
        result.abstractType = abs;
        final activeAbs = queries.activeAbstract();
        final activeName = queries.activeFieldName();
        final activeField = activeAbs != null && activeName != null ? queries.activeField(activeAbs, activeName) : null;
        result.nativeOperator = activeAbs != null && activeField != null
            && ValueTypeSupport.sameAbstract(activeAbs, abs)
            && ValueTypeSupport.operatorOf(abs, activeField) != null;
        switch (queries.stripValue(value).expr) {
            case TBinop(op, left, right):
                result.kind = ValueTypeBinary(op, left, right);
                result.field = ValueTypeSupport.binaryOperatorField(abs, op);
                result.wrapperRequired = queries.wrapNative && result.nativeOperator
                    && result.field != null && activeName != null && result.field.name == activeName;
            case TUnop(op, _, subject):
                result.kind = ValueTypeUnary(op, subject);
                result.field = ValueTypeSupport.unaryOperatorField(abs, op);
                result.wrapperRequired = queries.wrapNative && result.nativeOperator
                    && result.field != null && activeName != null && result.field.name == activeName;
            case _:
        }
        return result;
    }

    private function new() {}
}
#end
