package std;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

/**
 * Stage 1 build macro for the printed member of class records
 * (docs/specs/features/31-record-tostring-member.md). The generated field
 * carries a marker so Kotlin can keep its native data-class synthesis.
 */
class RecordMember {
    macro public static function build():Array<Field> {
        final fields = Context.getBuildFields();
        final localClass = Context.getLocalClass();
        if (localClass == null) {
            return fields;
        }
        final cls = localClass.get();
        // Feature spec 40 ruling 4: the stage 1 reference build rewrites
        // payload-enum Std.string operands into the labeled switch; the
        // generated targets keep the interception of feature spec 34 and
        // never define boring_oracle.
        if (Context.defined("boring_oracle")) {
            EnumText.rewriteStringCalls(fields);
        }
        // Spec 32 rule 2: the bare-name singleton form belongs to a class
        // with no instance fields. A field-carrying class whose constructor
        // parameters all hold defaults constructs with zero arguments too,
        // and keeps the spec 31 labeled form through @:dataClass instead.
        final singleton = !declaresInstanceFields(fields) && hasSelfConstructionStatic(fields, cls);
        if (!singleton && !cls.meta.has(":dataClass")) {
            return fields;
        }

        for (field in fields) {
            if (field.name != "toString") {
                continue;
            }
            switch (field.kind) {
                case FFun(fun) if (fun.args.length == 0):
                    return fields;
                case _:
            }
        }

        if (singleton) {
            final pos = Context.currentPos();
            final body:Expr = {
                expr: EBlock([
                    {
                        expr: EReturn({expr: EConst(CString(cls.name)), pos: pos}),
                        pos: pos
                    }
                ]),
                pos: pos
            };
            fields.push({
                name: "toString",
                doc: "Synthesized singleton printed form.",
                meta: [{name: ":recordMember", params: [], pos: pos}],
                access: [APublic],
                kind: FFun({args: [], ret: macro :String, expr: body}),
                pos: pos
            });
            return fields;
        }

        final shape = RecordShape.local(fields);
        final pos = Context.currentPos();
        final receiver:Expr = {expr: EConst(CIdent("this")), pos: pos};
        final printed = RecordShape.assemble(receiver, shape);
        final body:Expr = {
            expr: EBlock([{expr: EReturn(printed), pos: pos}]),
            pos: pos
        };
        fields.push({
            name: "toString",
            doc: "Synthesized record printed form.",
            meta: [{name: ":recordMember", params: [], pos: pos}],
            access: [APublic],
            kind: FFun({args: [], ret: macro :String, expr: body}),
            pos: pos
        });
        return fields;
    }

    static function hasSelfConstructionStatic(fields:Array<Field>, cls:ClassType):Bool {
        for (field in fields) {
            if (field.access.indexOf(AStatic) < 0 || field.access.indexOf(AFinal) < 0) {
                continue;
            }
            final declared:Null<ComplexType> = switch (field.kind) {
                case FVar(type, _): type;
                case _: null;
            };
            final initializer:Null<Expr> = switch (field.kind) {
                case FVar(_, expr): expr;
                case _: null;
            };
            if (declared == null || initializer == null) {
                continue;
            }
            final declaredType = Context.follow(Context.resolveType(declared, field.pos));
            final unwrapped = stripDecorations(initializer);
            switch (unwrapped.expr) {
                case ENew(path, args) if (args.length == 0):
                    final constructedType = Context.follow(Context.resolveType(TPath(path), unwrapped.pos));
                    if (isLocalClass(declaredType, cls) && isLocalClass(constructedType, cls)) {
                        return true;
                    }
                case _:
            }
        }
        return false;
    }

    static function declaresInstanceFields(fields:Array<Field>):Bool {
        for (field in fields) {
            if (field.access.indexOf(AStatic) >= 0) {
                continue;
            }
            switch (field.kind) {
                case FVar(_, _) | FProp(_, _, _, _):
                    return true;
                case _:
            }
        }
        return false;
    }

    static function isLocalClass(type:Type, cls:ClassType):Bool {
        return switch (type) {
            case TInst(ref, _): final other = ref.get(); other.module == cls.module && other.name == cls.name;
            case _:
                false;
        };
    }

    static function stripDecorations(expr:Expr):Expr {
        return switch (expr.expr) {
            case EMeta(_, inner) | EParenthesis(inner): stripDecorations(inner);
            case _: expr;
        };
    }
}
#end
