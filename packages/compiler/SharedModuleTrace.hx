#if (macro || reflaxe_runtime)
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.macro.Context;
import sys.io.File;

/**
    Runtime trace of the shared compiler mechanisms listed in
    SemanticPassRegistry (features 09, 20, 23, 24, 27, 28, 32 and the
    cross-target mechanisms behind standard library/05, 06 and 17).

    The registry used to prove consumption by matching module names in the
    target compiler source. That check cannot tell a module that is imported
    and never called from a target that ships its own copy: both pass. This
    module answers the behavioural question instead. The public entry points
    of every registered module record the calling class when they run, so a
    compilation that never reaches a mechanism leaves no record.

    Recording is off unless `-D shared-module-trace=<path>` names an output
    file and `-D shared-module-trace-target=<target>` names the target under
    test. The flush writes one `module<TAB>caller` line per distinct pair.
    Without the defines every record call returns before touching the stack,
    so the ordinary `gen:all` build is unchanged.

    The caller is the first stack frame outside the recording module. That
    keeps attribution at the direct consumer: a target that reaches
    EnumCycleDetector through PolicyQueries records PolicyQueries as the
    consumer, which is exactly the registry's consumer column. A module whose
    expected consumers never appear is a bypass.
**/
class SharedModuleTrace {
    /** Define whose value is the trace output path. */
    public static final DEFINE = "shared-module-trace";

    /** Define whose value is the target under test (dart, kotlin, rust, swift, ts). */
    public static final TARGET_DEFINE = "shared-module-trace-target";

    /** This class records nothing, or it would recurse into itself. */
    static final SELF = "SharedModuleTrace";

    /** Distinct `module<TAB>caller` pairs. */
    static var records:Map<String, Bool> = new Map();

    /** Modules that already recorded a caller from the target under test. */
    static var found:Map<String, Bool> = new Map();

    static var installed:Bool = false;

    /**
        True while the trace define names a writable path. A bare
        `-D shared-module-trace` (value `1`) stays off: no path means no
        artifact and no way to assert.
    **/
    public static function enabled():Bool {
        #if macro
        final value = Context.definedValue(DEFINE);
        return value != null && value != "" && value != "1";
        #else
        return false;
        #end
    }

    /** Record one call of `module` by its direct caller. */
    public static function record(module:String):Void {
        #if macro
        if (!enabled()) {
            return;
        }
        final target = Context.definedValue(TARGET_DEFINE);
        if (target == null || target == "") {
            return;
        }
        // A module the registry does not expect from this target is not a
        // consumer; skipping it keeps the stack capture off the hot path of
        // the shared-to-shared calls every target makes.
        if (!SemanticPassRegistry.expected(module, target)) {
            return;
        }
        // One target caller is enough to prove consumption; later calls of
        // the same module need no stack.
        if (found.exists(module)) {
            return;
        }
        final caller = callerOf(module);
        if (caller == null) {
            return;
        }
        records.set(module + "\t" + caller, true);
        if (isTargetCaller(caller, target)) {
            found.set(module, true);
        }
        #end
    }

    /**
        The first stack frame outside `module`. Consecutive frames of the
        recording module are its own helpers and are skipped; the next frame
        is either another shared module (an intra-compiler call, filtered by
        the consumer column) or target compiler code (a direct consumer).
    **/
    static function callerOf(module:String):Null<String> {
        var inModule = false;
        for (item in CallStack.callStack()) {
            final className = methodClass(item);
            if (className == null || className == SELF) {
                continue;
            }
            if (!inModule) {
                if (className == module) {
                    inModule = true;
                    continue;
                }
                return className;
            }
            if (className == module) {
                continue;
            }
            return className;
        }
        return null;
    }

    /**
        The class name of one stack item. The eval host wraps every entry in
        a FilePos, so unwrap until the Method frame appears.
    **/
    static function methodClass(item:Null<StackItem>):Null<String> {
        if (item == null) {
            return null;
        }
        return switch (item) {
            case Method(className, _): className;
            case FilePos(inner, _, _, _): methodClass(inner);
            default: null;
        };
    }

    /** Whether `caller` is a class of the target compiler under test. */
    static function isTargetCaller(caller:String, target:String):Bool {
        return caller.substr(0, target.length + 1) == target + ".";
    }

    /**
        Register the flush. `Intercept.run` calls this once per compilation;
        reflaxe registers its own after-generate hook first, so the trace file
        is written after target generation has run every consumer.
    **/
    public static function install():Void {
        #if macro
        if (!enabled() || installed) {
            return;
        }
        installed = true;
        Context.onAfterGenerate(flush);
        #end
    }

    static function flush():Void {
        #if macro
        final path = Context.definedValue(DEFINE);
        if (path == null || path == "" || path == "1") {
            return;
        }
        final keys = [for (key in records.keys()) key];
        keys.sort(Reflect.compare);
        final buffer = new StringBuf();
        for (key in keys) {
            buffer.add(key);
            buffer.add("\n");
        }
        File.saveContent(path, buffer.toString());
        #end
    }
}
#end
