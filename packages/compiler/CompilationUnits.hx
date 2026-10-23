#if (macro || reflaxe_runtime)

import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;

/**
    The unit a generated target emits a module into:
      - main  : the shipping tree.
      - tests : the test tree (modules holding @:test functions, and, on
                Kotlin, conventional class test entries).

    The unit is a coarse grouping used by cross-module reachability checks.
**/
enum abstract UnitId(String) {
    var Main = "main";
    var Tests = "tests";
}

/**
    Compilation-unit topology for generated targets.

    A unit must be resolved BEFORE expression rendering begins. The target's
    own test routing uses per-class maps that are populated during
    addClassesToCompiler, which interleaves with expression lowering; reading
    those maps too early is the primary bug this module exists to avoid. Each
    target therefore calls registerFromModuleTypes in its preScan
    (onAfterTyping), which runs before lowering and scans the raw typed
    declarations.

    On top of the raw @:test / class-entry scan, registerFromModuleTypes also
    computes the test-support closure: a main-unit module whose every referencer
    lives in the tests unit is reclassified to tests. This is what moves
    golden-data and *TestSupport modules (no @:test of their own, referenced
    only by test code) out of the shipping tree without a per-target split.
    @:testOnly forces a module to tests and @:mainOnly pins a module to main,
    both escape hatches around the closure.
**/
class CompilationUnits {
    public static final DEFAULT_UNIT:UnitId = Main;

    static final units:Map<String, UnitId> = [];

    /** Modules pinned to Main by @:mainOnly; the closure never reclassifies them. */
    static final pinnedMain:Map<String, Bool> = [];

    /**
        Record module as belonging to unit. Tests always wins over a
        previously recorded Main: a module whose file also declares helper
        typedefs/enums is still a test module.
    **/
    public static function register(module:String, unit:UnitId):Void {
        if (unit == Tests || !units.exists(module)) {
            units.set(module, unit);
        }
    }

    public static function unitOf(module:String):UnitId {
        return units.exists(module) ? units.get(module) : DEFAULT_UNIT;
    }

    public static function isTestModule(module:String):Bool {
        return unitOf(module) == Tests;
    }

    public static function isMainModule(module:String):Bool {
        return unitOf(module) == Main;
    }

    public static function sameUnit(a:String, b:String):Bool {
        return unitOf(a) == unitOf(b);
    }

    /** True when a lives in the test tree, which runs on top of the main
        tree. */
    public static function dependsOn(a:String, b:String):Bool {
        return unitOf(a) == Tests && unitOf(b) == Main;
    }

    /**
        Classify every typed module BEFORE the target lowers any class. The
        detection mirrors each target's own routing without depending on the
        late-arriving test maps:

          - @:test on any function flags the module as tests (all targets).
          - The conventional runTestEntries class entry flags the module as
            tests on Kotlin (includeClassEntries=true), matching isTestModule.
          - @:testOnly forces tests and @:mainOnly pins main (closure escape
            hatches).

        Afterwards the test-support closure reclassifies main modules whose
        referencers are all already-test modules (a single pass, not a
        fixpoint).
    **/
    public static function registerFromModuleTypes(mtypes:Array<ModuleType>, includeClassEntries:Bool):Void {
        pinnedMain.clear();
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c): {
                    final cls = c.get();
                    if (cls.meta.has(":testOnly")) {
                        register(cls.module, Tests);
                    } else if (cls.meta.has(":mainOnly")) {
                        pinnedMain.set(cls.module, true);
                        register(cls.module, Main);
                    } else {
                        final isTest = hasTestMethods(cls)
                            || (includeClassEntries && hasClassEntry(cls));
                        register(cls.module, isTest ? Tests : Main);
                    }
                }
                case TEnumDecl(en):
                    classifyDecl(en.get().module, en.get().meta);
                case TTypeDecl(t):
                    classifyDecl(t.get().module, t.get().meta);
                case TAbstract(a):
                    classifyDecl(a.get().module, a.get().meta);
            }
        }
        computeTestClosure(mtypes);
    }

    /** The default classification of a non-class declaration: testOnly forces
        tests, mainOnly pins main, otherwise main. */
    static function classifyDecl(module:String, meta:MetaAccess):Void {
        if (meta.has(":testOnly")) {
            register(module, Tests);
        } else if (meta.has(":mainOnly")) {
            pinnedMain.set(module, true);
            register(module, Main);
        } else {
            register(module, Main);
        }
    }

    /**
        Single pass over the pass-1 classification: a main module (not
        @:mainOnly) whose referencer set is non-empty and wholly inside tests
        becomes tests. Self-references and references from modules outside the
        typed set are ignored, so unreferenced main modules (entry points,
        forced-through-typing residents) stay main.
    **/
    static function computeTestClosure(mtypes:Array<ModuleType>):Void {
        final referencers:Map<String, Map<String, Bool>> = [];
        function note(from:String, to:String):Void {
            if (from == null || to == null || from == to) {
                return;
            }
            if (!referencers.exists(to)) {
                referencers.set(to, []);
            }
            referencers.get(to).set(from, true);
        }
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c): collectClassRefs(c.get(), note);
                case TEnumDecl(en): collectEnumRefs(en.get(), note);
                case TTypeDecl(t): collectTypedefRefs(t.get(), note);
                case TAbstract(a): collectAbstractRefs(a.get(), note);
            }
        }
        // Single pass over the pass-1 classification: a main module whose every
        // referencer is already a test module is reclassified. This is NOT a
        // fixpoint: iterating to a fixpoint would collapse a whole library whose
        // only roots are test modules (every core module becomes reachable only
        // from tests and the shipping tree empties out).
        final reclassified:Array<String> = [];
        for (module in units.keys()) {
            if (units.get(module) != Main) {
                continue;
            }
            if (pinnedMain.exists(module)) {
                continue;
            }
            final refs = referencers.get(module);
            if (refs == null) {
                continue;
            }
            var allTests = true;
            for (src in refs.keys()) {
                if (unitOf(src) != Tests) {
                    allTests = false;
                    break;
                }
            }
            if (allTests) {
                reclassified.push(module);
            }
        }
        for (module in reclassified) {
            units.set(module, Tests);
            Context.warning("compilation unit: module " + module
                + " reclassified to tests (every referencer is a test module)",
                Context.currentPos());
        }
    }

    static function collectClassRefs(cls:ClassType, note:String->String->Void):Void {
        final from = cls.module;
        if (cls.superClass != null) {
            note(from, cls.superClass.t.get().module);
        }
        for (iface in cls.interfaces) {
            note(from, iface.t.get().module);
        }
        for (f in cls.statics.get()) {
            collectTypeModules(f.type, from, note);
            final e = f.expr();
            if (e != null) {
                collectExprRefs(e, from, note);
            }
        }
        for (f in cls.fields.get()) {
            collectTypeModules(f.type, from, note);
            final e = f.expr();
            if (e != null) {
                collectExprRefs(e, from, note);
            }
        }
        if (cls.constructor != null) {
            final ctor = cls.constructor.get();
            collectTypeModules(ctor.type, from, note);
            final e = ctor.expr();
            if (e != null) {
                collectExprRefs(e, from, note);
            }
        }
    }

    static function collectEnumRefs(en:EnumType, note:String->String->Void):Void {
        final from = en.module;
        for (ef in en.constructs) {
            if (ef.type != null) {
                collectTypeModules(ef.type, from, note);
            }
        }
    }

    static function collectTypedefRefs(def:DefType, note:String->String->Void):Void {
        collectTypeModules(def.type, def.module, note);
    }

    static function collectAbstractRefs(abs:AbstractType, note:String->String->Void):Void {
        final from = abs.module;
        if (abs.type != null) {
            collectTypeModules(abs.type, from, note);
        }
        // The abstract's statics and instance methods live on its synthetic
        // impl class, which shares the abstract's own module.
        if (abs.impl != null) {
            collectClassRefs(abs.impl.get(), note);
        }
    }

    /** Walk a typed Type, recording the module of every named declaration it
        reaches (classes, enums, typedefs, abstracts) and their parameters. */
    static function collectTypeModules(t:Null<Type>, from:String, note:String->String->Void):Void {
        if (t == null) {
            return;
        }
        switch (t) {
            case TInst(c, params):
                note(from, c.get().module);
                for (p in params) collectTypeModules(p, from, note);
            case TEnum(e, params):
                note(from, e.get().module);
                for (p in params) collectTypeModules(p, from, note);
            case TType(d, params):
                note(from, d.get().module);
                for (p in params) collectTypeModules(p, from, note);
                collectTypeModules(d.get().type, from, note);
            case TAbstract(a, params):
                note(from, a.get().module);
                for (p in params) collectTypeModules(p, from, note);
            case TFun(args, ret):
                for (a in args) collectTypeModules(a.t, from, note);
                collectTypeModules(ret, from, note);
            case TAnonymous(anon):
                for (f in anon.get().fields) collectTypeModules(f.type, from, note);
            case TDynamic(t2):
                collectTypeModules(t2, from, note);
            case TLazy(f):
                collectTypeModules(f(), from, note);
            case TMono(_):
        }
    }

    /** Walk a typed expression: its static type plus explicit static/instance
        field, constructor, and type-expression references. */
    static function collectExprRefs(e:TypedExpr, from:String, note:String->String->Void):Void {
        if (e == null) {
            return;
        }
        collectTypeModules(e.t, from, note);
        switch (e.expr) {
            case TField(_, FStatic(c, _)):
                note(from, c.get().module);
            case TField(_, FInstance(owner, _, _)):
                note(from, owner.get().module);
            case TNew(c, _, _):
                note(from, c.get().module);
            case TTypeExpr(TClassDecl(c)):
                note(from, c.get().module);
            case TTypeExpr(TEnumDecl(en)):
                note(from, en.get().module);
            case _:
        }
        TypedExprTools.iter(e, child -> collectExprRefs(child, from, note));
    }

    static function hasTestMethods(cls:ClassType):Bool {
        return hasTestField(cls.statics.get())
            || hasTestField(cls.fields.get());
    }

    static function hasTestField(fields:Array<ClassField>):Bool {
        for (f in fields) {
            if (f.meta.has(":test")) {
                return true;
            }
        }
        return false;
    }

    static function hasClassEntry(cls:ClassType):Bool {
        for (f in cls.statics.get()) {
            if (isEntryField(f)) {
                return true;
            }
        }
        return false;
    }

    static inline function isEntryField(f:ClassField):Bool {
        return f.name == "runTestEntries"
            && !f.meta.has(":test");
    }

    /**
        Write the unit table as TSV (module<TAB>unit), one sorted line per
        module. Written only to the -D compilation_units_dump side channel,
        never into target output, so GP-DIFF stays byte-identical.
    **/
    public static function dump(modules:Array<String>, path:String):Void {
        final ordered = modules.copy();
        ordered.sort(Reflect.compare);
        final lines:Array<String> = [
            for (m in ordered) m + "\t" + unitOf(m)
        ];
        final dir = haxe.io.Path.directory(path);
        if (dir != null && dir != "" && !sys.FileSystem.exists(dir)) {
            sys.FileSystem.createDirectory(dir);
        }
        sys.io.File.saveContent(
            path,
            lines.join("\n") + (lines.length > 0 ? "\n" : "")
        );
    }

    public static function dumpIfRequested(modules:Array<String>):Void {
        final path = Context.definedValue("compilation_units_dump");
        if (path != null) {
            dump(modules, path);
        }
    }
}

#end
