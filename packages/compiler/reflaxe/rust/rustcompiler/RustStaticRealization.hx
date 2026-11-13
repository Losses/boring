package rustcompiler;

import haxe.macro.Context;
import haxe.macro.Expr.Position;

/**
    The three static/global realizations of the Rust target.

    A static or global MUST declare exactly one mode, and the emitted Rust
    item must match that declaration. modeOf classifies a Haxe static from
    the facts the emitter already computes; verifyItem checks the rendered
    item text against the declared mode, so an inconsistency fails
    generation and never reaches the crate.
**/
class RustStaticRealization {
    /**
        The policy rule this file implements. The same text is normative in
        docs/specs/target-semantic-policy.md (P-1a).
    **/
    public static final POLICY_RULE:String = "Static/global realization MUST declare ImmutableLazy, ThreadAffine, or ThreadSafeShared.
ImmutableLazy uses LazyLock<T> only when T satisfies required Rust auto-traits.
ThreadAffine is !Send and !Sync and cannot be placed in a process-global Sync static; access requires designated owner thread.
ThreadSafeShared uses LazyLock<Arc<Mutex<T>>> or equivalent safe primitive and must not contain Rc/RefCell.
An unconditional unsafe Send/Sync implementation for a wrapper containing Rc/RefCell is forbidden.
Target configuration and test harness must select the same mode; parallel tests are unsupported for ThreadAffine until an owner-thread harness exists.";

    public static function name(mode:StaticRealizationMode):String {
        return switch (mode) {
            case ImmutableLazy: "ImmutableLazy";
            case ThreadAffine: "ThreadAffine";
            case ThreadSafeShared: "ThreadSafeShared";
        };
    }

    /**
        The mode of one static from the facts the emitter derived from the
        declaration:

        - handleBacked: the rendered Rust type names an Rc<RefCell<..>> slot,
          directly or nested in a container.
        - nonSend: the rendered Rust type names an Rc<dyn ..> or Box<dyn ..>
          value that no process-global Sync slot can carry safely.
        - lazyBacked: the initializer cannot be a const expression, so the
          value builds on first access (LazyLock).
        - directArray: a final array of Int literals, emitted as a plain
          immutable array static.

        A ThreadAffine value holds the Haxe single-threaded semantics inside
        one owner thread. An ImmutableLazy value is immutable and satisfies
        the Rust auto traits its LazyLock slot needs. Everything else is a
        ThreadSafeShared process slot.
    **/
    public static function modeOf(handleBacked:Bool, nonSend:Bool, lazyBacked:Bool, directArray:Bool):StaticRealizationMode {
        if (handleBacked || nonSend)
            return ThreadAffine;
        if (lazyBacked || directArray)
            return ImmutableLazy;
        return ThreadSafeShared;
    }

    /**
        The test harness configuration. -D rust-test-threads names the harness
        the generated crate is tested under: serial (default) runs every test
        on the owner thread, parallel runs the cargo default scheduler.

        A ThreadAffine static belongs to its owner thread, so the parallel
        harness is unsupported while one is present: the compilation is
        rejected, and no crate with a per-test-thread static state is produced.

        The define accepts only "serial" and "parallel". Any other value,
        including the "1" a bare `-D rust-test-threads` sets, is a generation
        error: an unrecognized value would otherwise select neither harness
        and silently leave the parallel scheduler in place.
    **/
    public static function checkHarness(mode:StaticRealizationMode, label:String, pos:Position):Void {
        final setting = Context.definedValue("rust-test-threads");
        if (setting != null && setting != "serial" && setting != "parallel") {
            Context.error("-D rust-test-threads names the test harness and must be serial or parallel, got \"" + setting + "\".", pos);
            return;
        }
        if (mode != ThreadAffine || setting == null || setting == "serial")
            return;
        Context.error("static " + label + " is ThreadAffine; -D rust-test-threads=parallel is unsupported because the owner-thread slot of a ThreadAffine static belongs to one thread. Run the serial harness (-D rust-test-threads=serial, the default).", pos);
    }

    /**
        The rendered item must match the declared mode. The checks are on the
        Rust text so every emission path is covered by the same gate:

        - ImmutableLazy carries no interior mutability and no lock.
        - ThreadAffine is a thread_local slot and never a process-global
          LazyLock or Mutex.
        - ThreadSafeShared carries a Mutex and never an Rc or RefCell.
    **/
    public static function verifyItem(mode:StaticRealizationMode, item:String, label:String, pos:Position):Bool {
        final hasRc = item.indexOf("Rc<") >= 0;
        final hasRefCell = item.indexOf("RefCell<") >= 0;
        final hasMutex = item.indexOf("Mutex<") >= 0;
        final hasLazyLock = item.indexOf("LazyLock<") >= 0;
        final hasThreadLocal = item.indexOf("thread_local!") >= 0;
        switch (mode) {
            case ImmutableLazy:
                if (hasMutex || hasRefCell || hasThreadLocal) {
                    Context.error("static " + label + " declares ImmutableLazy but its Rust item carries interior mutability or a lock: " + item, pos);
                    return false;
                }
            case ThreadAffine:
                if (!hasThreadLocal || !(hasRc || hasRefCell)) {
                    Context.error("static " + label + " declares ThreadAffine but its Rust item is not a thread_local slot over Rc/RefCell: " + item, pos);
                    return false;
                }
                if (hasMutex || hasLazyLock) {
                    Context.error("static " + label + " declares ThreadAffine but its Rust item places the value in a process-global slot: " + item, pos);
                    return false;
                }
            case ThreadSafeShared:
                if (!hasMutex) {
                    Context.error("static " + label + " declares ThreadSafeShared but its Rust item carries no Mutex: " + item, pos);
                    return false;
                }
                if (hasRc || hasRefCell) {
                    Context.error("static " + label + " declares ThreadSafeShared but its Rust item contains Rc/RefCell: " + item, pos);
                    return false;
                }
        }
        return true;
    }
}
