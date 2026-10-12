#if (macro || reflaxe_runtime)

import haxe.macro.Context;
import haxe.macro.Type;

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
**/
class CompilationUnits {
    public static final DEFAULT_UNIT:UnitId = Main;

    static final units:Map<String, UnitId> = [];

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
    **/
    public static function registerFromModuleTypes(mtypes:Array<ModuleType>, includeClassEntries:Bool):Void {
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c): {
                    final cls = c.get();
                    final isTest = hasTestMethods(cls)
                        || (includeClassEntries && hasClassEntry(cls));
                    register(cls.module, isTest ? Tests : Main);
                }
                case TEnumDecl(en):
                    register(en.get().module, Main);
                case TTypeDecl(t):
                    register(t.get().module, Main);
                case TAbstract(a):
                    register(a.get().module, Main);
            }
        }
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
