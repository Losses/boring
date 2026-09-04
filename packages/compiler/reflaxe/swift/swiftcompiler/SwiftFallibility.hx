package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;

/**
    Computes the throw set of every function in source scope, the Swift
    side of features/06. Swift propagates faults through `throws`
    signatures, so emission needs the fallibility of every function
    before any body renders. Direct throws, the faulting operations of
    stdlib/08, and the resident raise of TestPlatform infect the calling
    function; the property then spreads through call edges until
    nothing changes. A try region absorbs exactly the exception classes
    its catches name: calls inside the region only infect the caller
    with the classes no enclosing catch handles.
**/
class SwiftFallibility {
    /** The synthetic error domain of the test-host raise. */
    public static final TEST_FAILURE = "swift.TestFailure";

    /**
        The synthetic domain of the bare rethrow footer every lowered try
        region carries: a try that names specific classes rethrows
        whatever it does not catch (features/06), and no named catch
        absorbs that unknown domain.
    **/
    static final RETHROWN = "swift.RethrownError";

    static final INFECTION_SOURCE = "std.UStringException";

    /** funcKey to the exception-class modules that escape it. */
    static final escaping:Map<String, Map<String, Bool>> = [];

    static final bodies:Array<{key:String, body:TypedExpr}> = [];

    /** The unique key of one function; the subset has no overloads. */
    public static function funcKey(module:String, name:String, isStatic:Bool):String {
        return module + "." + name + (isStatic ? ":static" : ":instance");
    }

    /**
        Collects every function body of the module types. Runs from
        onAfterTyping, before generation callbacks, so the fixed point
        settles before the first declaration renders.
    **/
    public static function collect(mtypes:Array<ModuleType>):Void {
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c):
                    final cls = c.get();
                    final resident = RuntimeResidents.isResident(cls.module);
                    if (cls.isExtern
                        || (!resident && !inScope(cls.pos))
                        || (StringTools.endsWith(cls.name, "_Impl_") && ValueTypeSupport.markedAbstractOfClass(cls) == null)) {
                        continue;
                    }
                    for (field in cls.statics.get()) {
                        addBody(cls.module, field, true);
                    }
                    for (field in cls.fields.get()) {
                        addBody(cls.module, field, false);
                    }
                    // The constructor sits outside `fields` on
                    // `cls.constructor`; its body joins the analysis so a
                    // throwing constructor infects its callers (feature
                    // spec 27).
                    final ctor = cls.constructor;
                    if (ctor != null) {
                        addBody(cls.module, ctor.get(), false);
                    }
                case _:
            }
        }
        resolve();
    }

    static function addBody(module:String, field:ClassField, isStatic:Bool):Void {
        switch (field.kind) {
            case FMethod(_):
                final expr = field.expr();
                if (expr != null) {
                    bodies.push({key: funcKey(module, field.name, isStatic), body: expr});
                }
            case _:
        }
    }

    /** Fixed point over call edges. */
    static function resolve():Void {
        var changed = true;
        while (changed) {
            changed = false;
            for (entry in bodies) {
                final infections:Map<String, Bool> = [];
                scanExpr(entry.body, [], infections);
                final current = escaping.exists(entry.key) ? escaping.get(entry.key) : new Map<String, Bool>();
                for (domain in infections.keys()) {
                    if (!current.exists(domain)) {
                        current.set(domain, true);
                        changed = true;
                    }
                }
                escaping.set(entry.key, current);
            }
        }
    }

    /**
        Walks one expression tree collecting the exception domains that
        escape it. `absorbed` holds the classes enclosing try regions
        catch; a throw or a callee escape inside those classes never
        reaches the function edge.
    **/
    static function scanExpr(e:TypedExpr, absorbed:Array<String>, infections:Map<String, Bool>):Void {
        switch (e.expr) {
            case TTry(body, catches):
                final caught = absorbed.copy();
                for (c in catches) {
                    final domain = classDomainOf(c.v.t);
                    if (domain != null && caught.indexOf(domain) < 0) {
                        caught.push(domain);
                    }
                }
                scanExpr(body, caught, infections);
                for (c in catches) {
                    scanExpr(c.expr, absorbed, infections);
                }
                if (!hasCatchAll(catches)) {
                    // The lowering appends a bare catch that rethrows
                    // unmatched errors; the rethrown class is unknown
                    // here, so it escapes as a domain nothing absorbs.
                    infections.set(RETHROWN, true);
                }
            case TThrow(x):
                final domain = classDomainOf(x.t);
                if (domain != null && absorbed.indexOf(domain) < 0) {
                    infections.set(domain, true);
                }
            case TCall(fn, _):
                scanCall(fn, absorbed, infections);
                TypedExprTools.iter(e, x -> scanExpr(x, absorbed, infections));
            case TNew(c, _, _):
                // A construction is a call edge into the class constructor
                // (feature spec 27); the constructor's escaping domains
                // infect the calling function.
                final ctor = escaping.exists(funcKey(c.get().module, "new", false)) ? escaping.get(funcKey(c.get().module, "new", false)) : null;
                if (ctor != null) {
                    for (domain in ctor.keys()) {
                        infect(infections, absorbed, domain);
                    }
                }
                TypedExprTools.iter(e, x -> scanExpr(x, absorbed, infections));
            case _:
                TypedExprTools.iter(e, x -> scanExpr(x, absorbed, infections));
        }
    }

    static function scanCall(fn:TypedExpr, absorbed:Array<String>, infections:Map<String, Bool>):Void {
        switch (fn.expr) {
            case TField(subj, FStatic(c, cf)):
                final cls = c.get();
                final name = cf.get().name;
                if (SwiftTestBinding.isTestPlatformExtern(cls.module) && name == "raise") {
                    infect(infections, absorbed, TEST_FAILURE);
                    return;
                }
                if (SwiftTestBinding.isTestExternModule(cls.module, name)) {
                    infect(infections, absorbed, TEST_FAILURE);
                    return;
                }
                final callee = escaping.exists(routedFuncKey(cls.module, name, true)) ? escaping.get(routedFuncKey(cls.module, name, true)) : null;
                if (callee != null) {
                    for (domain in callee.keys()) {
                        infect(infections, absorbed, domain);
                    }
                }
            case TField(subj, FInstance(c, _, cf)):
                final owner = c.get();
                final name = cf.get().name;
                if (isStringBufMethodCall(subj, name)) {
                    infect(infections, absorbed, INFECTION_SOURCE);
                    return;
                }
                final callee = escaping.exists(funcKey(owner.module, name, false)) ? escaping.get(funcKey(owner.module, name, false)) : null;
                if (callee != null) {
                    for (domain in callee.keys()) {
                        infect(infections, absorbed, domain);
                    }
                }
            case _:
        }
    }

    static function infect(infections:Map<String, Bool>, absorbed:Array<String>, domain:String):Void {
        if (absorbed.indexOf(domain) < 0) {
            infections.set(domain, true);
        }
    }

    /**
        The extern face receives a static call and maps it to the module the
        emission actually calls: the resident extern fronts route into
        the runtime package, everything else keeps its own module.
    **/
    public static function routedFuncKey(module:String, name:String, isStatic:Bool):String {
        return funcKey(routedModule(module, name), name, isStatic);
    }

    public static function routedModule(module:String, name:String):String {
        return switch (module) {
            case "std.UStringRT": "runtime.UString";
            case "std.Graphemes": "runtime.Graphemes";
            case _: module;
        }
    }

    static function isTestAssertion(name:String):Bool {
        return name == "ok" || name == "fail" || StringTools.startsWith(name, "equals");
    }

    /**
        Whether a resolved static call needs the `try` marker at its call
        site. Test assertions route to the throwing host wrappers; the
        resident extern fronts route into the runtime package; the
        platform primitives lower to inline throws and bare expressions
        that no try covers.
    **/
    public static function staticCallThrows(cls:ClassType, name:String):Bool {
        if (SwiftTestBinding.isTestExternModule(cls.module, name)) {
            return isTestAssertion(name);
        }
        if (cls.module == "std.UStringPlatform" || SwiftTestBinding.isTestPlatformExtern(cls.module)) {
            return false;
        }
        return isThrowing(routedModule(cls.module, name), name, true);
    }

    public static function isStringBufMethodCall(subj:TypedExpr, name:String):Bool {
        if (name != "add" && name != "addChar" && name != "toString") {
            return false;
        }
        return switch (Context.follow(subj.t)) {
            case TInst(c, _): final cls = c.get(); (cls.pack.join(".") == "std" && cls.name == "StringBuf") || (cls.pack.length == 0 && cls.name == "StringBuf");
            case _: false;
        };
    }

    /**
        Whether a catch list takes everything: a Dynamic catch or one on
        the shared exception base leaves the rethrow footer unreachable.
    **/
    static function hasCatchAll(catches:Array<{v:TVar, expr:TypedExpr}>):Bool {
        for (c in catches) {
            switch (Context.follow(c.v.t)) {
                case TDynamic(_):
                    return true;
                case TAbstract(a, _):
                    if (a.get().name == "Dynamic") {
                        return true;
                    }
                case TInst(cl, _):
                    final cls = cl.get();
                    final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
                    if (path == "haxe.Exception") {
                        return true;
                    }
                case _:
            }
        }
        return false;
    }

    static function classDomainOf(t:Null<Type>):Null<String> {
        if (t == null) {
            return null;
        }
        return switch (Context.follow(t)) {
            case TInst(c, _):
                final cls = c.get();
                cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
            case _: null;
        };
    }

    /** Whether a function can throw anything that escapes it. */
    public static function isThrowing(module:String, name:String, isStatic:Bool):Bool {
        final set = escaping.get(funcKey(module, name, isStatic));
        return set != null && hasAnyKey(set);
    }

    /** Whether a call to the named function needs the `try` marker. */
    public static function callThrows(module:String, name:String, isStatic:Bool):Bool {
        return isThrowing(module, name, isStatic);
    }

    static function inScope(pos:haxe.macro.Expr.Position):Bool {
        final file = Context.getPosInfos(pos).file;
        for (root in Intercept.sourceRoots()) {
            final prefix = root.charAt(root.length - 1) == "/" ? root : root + "/";
            if (StringTools.startsWith(file, prefix) || StringTools.startsWith(file, "./" + prefix) || file.indexOf("/" + prefix) >= 0) {
                return true;
            }
        }
        return false;
    }

    static function hasAnyKey(map:Map<String, Bool>):Bool {
        for (_ in map.keys()) {
            return true;
        }
        return false;
    }
}
#end
