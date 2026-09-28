#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import SourceContainerAnalysis;

/**
    Shared rules for feature 30 static field declarations.

    Static initializers deliberately stay a small, target-independent
    language.  The target emitters call `validatedInitializer` before
    raversing an initializer, so an unsupported expression cannot turn into
    a target-specific partial declaration.
**/
class StaticFieldHelper {
    public static inline final INVALID_INITIALIZER = "static field initializers accept null, literal, and empty array forms only";
    public static inline final INVALID_FINAL_INITIALIZER = "static field initializers accept null, literal, array, and construction forms only";
    public static inline final INVALID_ARGUMENT = "constructed static field arguments accept literal, enum, array, construction, static field, and static function forms only";

    public static function initializer(field:ClassField):Null<TypedExpr> {
        if (field == null || field.expr == null) {
            return null;
        }
        return field.expr();
    }

    public static function validatedInitializer(field:ClassField, declaringClass:Null<ClassType> = null):Null<TypedExpr> {
        final init = initializer(field);
        if (init == null || isSanctioned(init) || isSelfConstruction(field, declaringClass, init)) {
            return init;
        }
        if (field.isFinal && isNonEmptyArrayLiteral(init)) {
            if (arrayElementsAdmitted(init)) {
                return init;
            }
            Context.error(INVALID_ARGUMENT, field.pos);
            return null;
        }
        if (field.isFinal && isConstruction(init)) {
            if (isPrivateSelfConstruction(field, declaringClass, init)) {
                Context.error(INVALID_INITIALIZER, field.pos);
                return null;
            }
            if (!constructionArgumentsAdmitted(init)) {
                Context.error(INVALID_ARGUMENT, field.pos);
                return null;
            }
            return init;
        }
        Context.error(field.isFinal ? INVALID_FINAL_INITIALIZER : INVALID_INITIALIZER, field.pos);
        return null;
    }

    /** Whether a static final field is the sanctioned singleton spelling. */
    public static function isSelfConstruction(field:ClassField, declaringClass:Null<ClassType>, init:Null<TypedExpr> = null):Bool {
        if (field == null || declaringClass == null || !field.isFinal) {
            return false;
        }
        // Spec 32 rule 2: the singleton form belongs to a declaring class
        // with no instance fields. A zero-argument construction of a
        // field-carrying class is legal whenever every constructor
        // parameter holds a default (spec 22 completion), so the argument
        // count alone cannot carry the singleton meaning; such a static
        // is a constructed initializer of spec 35 instead.
        if (hasInstanceFields(declaringClass)) {
            return false;
        }
        final actual = init == null ? initializer(field) : init;
        if (actual == null) {
            return false;
        }
        return switch (stripDecorations(actual).expr) {
            case TNew(constructedRef, _, args) if (args.length == 0): final constructed = constructedRef.get(); final declared = switch (Context.follow(field.type)) {
                    case TInst(declaredRef, _): declaredRef.get();
                    case _: null;
                }; declared != null && sameClass(declared, declaringClass) && sameClass(constructed, declaringClass);
            case _:
                false;
        };
    }

    /** Whether a class declares any instance field (variable or property). */
    public static function hasInstanceFields(cls:Null<ClassType>):Bool {
        if (cls == null) {
            return false;
        }
        for (field in cls.fields.get()) {
            switch (field.kind) {
                case FVar(_, _):
                    return true;
                case _:
            }
        }
        return false;
    }

    /** Whether a class carries the sanctioned singleton static. */
    public static function hasSelfConstructionStatic(cls:Null<ClassType>):Bool {
        if (cls == null) {
            return false;
        }
        for (field in cls.statics.get()) {
            if (isSelfConstruction(field, cls)) {
                return true;
            }
        }
        return false;
    }

    static function sameClass(a:ClassType, b:ClassType):Bool {
        return a.module == b.module && a.name == b.name;
    }

    public static function isConstruction(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        return switch (stripDecorations(e).expr) {
            case TNew(_, _, _): true;
            case _: false;
        };
    }

    static function isPrivateSelfConstruction(field:ClassField, declaringClass:Null<ClassType>, init:TypedExpr):Bool {
        if (declaringClass == null)
            return false;
        return switch (stripDecorations(init).expr) {
            case TNew(c, _, _): final constructed = c.get(); if (!sameClass(constructed,
                    declaringClass)) return false; final ctor = constructed.constructor; ctor != null && !ctor.get().isPublic;
            case _: false;
        };
    }

    static function constructionArgumentsAdmitted(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        return switch (stripDecorations(e).expr) {
            case TNew(_, _, args): [for (a in args) if (!argumentAdmitted(a)) false].length == 0;
            case _: false;
        };
    }

    static function argumentAdmitted(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        return switch (stripDecorations(e).expr) {
            case TConst(TNull) | TConst(TBool(_)) | TConst(TInt(_)) | TConst(TFloat(_)) | TConst(TString(_)): true;
            case TArrayDecl(elements): [for (x in elements) if (!argumentAdmitted(x)) false].length == 0;
            case TNew(_, _, _): constructionArgumentsAdmitted(e);
            case TField(_, FStatic(_, _)): true;
            case TField(_, FEnum(_, _)): true;
            case TField(subject, FInstance(_, _, _)) | TField(subject, FAnon(_)):
                argumentAdmitted(subject);
            case TCall(fn, args):
                [for (a in args) if (!argumentAdmitted(a)) false].length == 0;

            case _: false;
        };
    }

    public static function isNonEmptyArrayLiteral(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        return switch (stripDecorations(e).expr) {
            case TArrayDecl(elements): elements.length > 0;
            case _: false;
        };
    }

    static function arrayElementsAdmitted(e:TypedExpr):Bool {
        return switch (stripDecorations(e).expr) {
            case TArrayDecl(elements): [for (x in elements) if (!argumentAdmitted(x)) false].length == 0;
            case _: false;
        };
    }

    public static function isIntLiteralArray(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        return switch (stripDecorations(e).expr) {
            case TArrayDecl(elements) if (elements.length > 0):
                [for (x in elements) if (!isIntLiteralElement(x)) false].length == 0;
            case _: false;
        };
    }

    static function isIntLiteralElement(e:TypedExpr):Bool {
        return switch (stripDecorations(e).expr) {
            case TConst(TInt(_)): true;
            case _: false;
        };
    }

    /**
        Whether the written type names the reserved read-only array source
        face. The read-only query keeps its wider optional scope: an explicit
        outer `Null<ReadOnlyArray<T>>` wrapper counts, because boundary
        checks written against the wrapper must still see the read-only face.
        Source identity and alias resolution come from
        `SourceContainerAnalysis`; this adapter adds no recognition of its
        own. Its legacy boolean maps an unresolved face to `false`; that
        answer does not prove a resolved non-container. Production callers
        consume typed class fields or expression types after Haxe typing.
    **/
    public static function isReadOnlyArrayType(t:Null<Type>):Bool {
        final facts = SourceContainerAnalysis.analyze(t);
        return switch (facts.face) {
            case ReadOnlyArrayFace(_): true;
            case _: false;
        };
    }

    /**
        The element type of the written container when the spelling carries
        no explicit outer `Null` wrapper. Both built-in containers qualify.
        A nullable payload stays inside the element type and is available
        through the analyzer's typed result for later consumers; this legacy
        query does not widen to optional containers. `null` also represents an
        unresolved input or a resolved non-container, so callers that need to
        distinguish those states must use `SourceContainerAnalysis.analyze`.
    **/
    public static function arrayElementType(t:Null<Type>):Null<Type> {
        final facts = SourceContainerAnalysis.analyze(t);
        if (!matchesNoExplicitWrapper(facts)) {
            return null;
        }
        return switch (facts.face) {
            case MutableArray(element): element;
            case ReadOnlyArrayFace(element): element;
            case _: null;
        };
    }

    /** Whether the written spelling names the container with no explicit
        outer `Null` wrapper. */
    static function matchesNoExplicitWrapper(facts:SourceContainerAnalysis.SourceContainerFacts):Bool {
        return switch (facts.wrapper) {
            case NoExplicitWrapper: true;
            case _: false;
        };
    }

    public static function isSanctioned(e:TypedExpr):Bool {
        return switch (stripDecorations(e).expr) {
            case TConst(TNull): true;
            case TConst(TBool(_)): true;
            case TConst(TInt(_)): true;
            case TConst(TFloat(_)): true;
            case TConst(TString(_)): true;
            case TArrayDecl(elements): elements.length == 0;
            case _: false;
        };
    }

    /** Whether an initializer is a bare null literal. */
    public static function isNullInitializer(e:Null<TypedExpr>):Bool {
        return e != null && switch (stripDecorations(e).expr) {
            case TConst(TNull): true;
            case _: false;
        };
    }

    public static function isConstValue(field:ClassField):Bool {
        if (field == null || !field.isFinal || !isScalarOrString(field.type)) {
            return false;
        }
        final init = initializer(field);
        if (init == null) {
            return false;
        }
        return switch (stripDecorations(init).expr) {
            case TConst(TBool(_)): true;
            case TConst(TInt(_)): true;
            case TConst(TFloat(_)): true;
            case TConst(TString(_)): true;
            case _: false;
        };
    }

    /**
        Whether the written type names the built-in mutable `Array` with no
        explicit outer `Null` wrapper. Recognition is by declaration
        identity from `SourceContainerAnalysis`, so a foreign declaration
        that shares the name `Array` stays distinct. Its legacy boolean maps
        an unresolved face or wrapper to `false`; callers must establish the
        typed-analysis phase before interpreting that result as a non-array.
    **/
    public static function isArrayType(t:Null<Type>):Bool {
        final facts = SourceContainerAnalysis.analyze(t);
        if (!matchesNoExplicitWrapper(facts)) {
            return false;
        }
        return switch (facts.face) {
            case MutableArray(_): true;
            case _: false;
        };
    }

    public static function isNullableType(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (t) {
            case TAbstract(a, _): a.get().name == "Null";
            case _: false;
        };
    }

    public static function isStringType(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (t) {
            case TInst(c, _): c.get().name == "String";
            case _: false;
        };
    }

    public static function isScalarOrString(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (t) {
            case TAbstract(a, _):
                switch (a.get().name) {
                    case "Int" | "Float" | "Bool": true;
                    case _: false;
                }
            case TInst(c, _): c.get().name == "String";
            case _: false;
        };
    }

    public static function stripDecorations(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripDecorations(inner);
            case _: e;
        };
    }
}
#end
