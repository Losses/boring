#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;

/** Shared structural dispatch for assignment targets. Renderers retain target-specific syntax and policy. */
enum AssignTargetFieldKind {
    Instance(owner:Ref<ClassType>, field:Ref<ClassField>);
    Anonymous(field:Ref<ClassField>);
}

class AssignTargetPlan {
    public static function assignTarget(e:TypedExpr,
            renderArray:(TypedExpr, TypedExpr)->String,
            renderStatic:(TypedExpr)->String,
            renderInstance:(TypedExpr, AssignTargetFieldKind, TypedExpr)->String,
            renderLocal:TVar->String,
            fail:(TypedExpr, String)->String):String {
        return switch (e.expr) {
            case TArray(arr, idx): renderArray(arr, idx);
            case TField(_, FStatic(_, _)): renderStatic(e);
            case TField(subj, FInstance(owner, _, field)):
                renderInstance(subj, Instance(owner, field), e);
            case TField(subj, FAnon(field)):
                renderInstance(subj, Anonymous(field), e);
            case TLocal(v): renderLocal(v);
            case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
                assignTarget(inner, renderArray, renderStatic, renderInstance, renderLocal, fail);
            case _: fail(e, "assignment target has no lowering");
        };
    }
}
#end
