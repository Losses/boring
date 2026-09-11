package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
    Registry of class level @:access(Target) grants seen during emission.
    A grant lets the annotated class read the target's private members;
    the target class widens granted private members to Swift internal so
    cross-class (and same-file peer-class) reads compile. Keyed by the
    target's full module path (module + "." + name).
**/
class AccessGrants {
    static final granted:Map<String, Bool> = [];

    public static function allow(target:String):Void {
        granted.set(target, true);
    }

    public static function has(target:String):Bool {
        return granted.exists(target);
    }

    /** Widened so a granted member may name it in its signature. */
    public static function mentionsPrivateType(t:Type):Bool {
        var found = false;
        function note(u:Type):Void {
            if (found) {
                return;
            }
            switch (Context.follow(u)) {
                case TInst(c, ps):
                    if (c.get().isPrivate) {
                        found = true;
                        return;
                    }
                    for (p in ps) {
                        note(p);
                    }
                case TEnum(_, ps):
                    for (p in ps) {
                        note(p);
                    }
                case TAbstract(_, ps):
                    for (p in ps) {
                        note(p);
                    }
                case TFun(args, ret):
                    for (a in args) {
                        note(a.t);
                    }
                    note(ret);
                case TAnonymous(a):
                    for (f in a.get().fields) {
                        note(f.type);
                    }
                case TLazy(f): note(f());
                case _:
            }
        }
        note(t);
        return found;
    }

    #if (macro || reflaxe_runtime)
    /**
        Pre-emission scan (runs from the compiler's onAfterTyping hook, like
        SwiftFallibility.collect): records every class level @:access(Target)
        grant before the first declaration renders, so grant order never
        depends on class emission order.
    **/
    public static function collect(mtypes:Array<ModuleType>):Void {
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c):
                    final cls = c.get();
                    if (cls.meta.has(":access")) {
                        for (m in cls.meta.get()) {
                            if (m.name != ":access" || m.params.length == 0) {
                                continue;
                            }
                            final target = grantTarget(m.params[0]);
                            if (target != null) {
                                allow(target);
                            }
                        }
                    }
                case _:
            }
        }
        collectDefaultStaticGrants();
    }

    /**
        A constructor or method default that names a private static (such as
        a `?? PrivateHelper.make()` coalescing default) is inlined at every
        call site, including call sites in other modules. The owning class
        must widen that static to internal or the cross-module reference
        breaks. Runs in the pre-emission scan so grant order never depends
        on class emission order.
    **/
    static function collectDefaultStaticGrants():Void {
        DefaultArgExpander.visitDefaultStaticTargets((modulePath, className, methodName) -> {
            if (isPrivateStatic(modulePath, className, methodName)) {
                allow(modulePath + "." + className);
            }
        });
    }

    static function isPrivateStatic(modulePath:String, className:String, methodName:String):Bool {
        final resolved:Null<Type> = try Context.getType(modulePath + "." + className) catch (_:Dynamic) null;
        return switch (resolved) {
            case TInst(c, _):
                var found = false;
                for (f in c.get().statics.get()) {
                    if (f.name == methodName) {
                        found = !f.isPublic && !f.meta.has(":allow");
                        break;
                    }
                }
                found;
            case _: false;
        }
    }

    static function grantTarget(e:Expr):Null<String> {
        final path = grantPath(e);
        if (path == null) {
            return null;
        }
        final resolved:Null<Type> = try Context.getType(path) catch (_:Dynamic) null;
        if (resolved == null) {
            return null;
        }
        return switch (Context.follow(resolved)) {
            case TInst(c, _): c.get().module + "." + c.get().name;
            case _: null;
        }
    }

    static function grantPath(e:Expr):Null<String> {
        return switch (e.expr) {
            case EField(inner, field):
                final head = grantPath(inner);
                head == null ? null : head + "." + field;
            case EConst(CIdent(name)): name;
            case _: null;
        }
    }
    #end
}
