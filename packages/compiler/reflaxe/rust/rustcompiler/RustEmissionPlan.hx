package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
    Pre-computed emission plan for the Rust target.
    Computed once at the start of Compiler.preScan so that
    scanFallibility, compileClassImpl, and includeStaticFunc
    all read one consistent answer instead of each maintaining
    its own copy of the emission logic.

    1. Which synthetic-impl classes emit: the referencedImplModules
       set replaces the state.referencedImpls read in both
       compileClassImpl (whole-class drop) and scanFallibility
       (skip registration).  It is populated by walking all
       in-scope class bodies at plan-construction time — the
       same walk scanReferencedImpls formerly performed.

    2. Which private static functions emit: the fieldEmit map
       replaces includeStaticFunc and the same-field gate in
       scanFallibility.  Instance members, public statics,
       @:test, and exception-subclass statics always emit,
       handled inside shouldEmitStaticField.

    At render end the superset assertion checks that every
    render-time write to state.referencedImpls (RustExpr.hx
    static call sites) was already predicted by the body-walk;
    a miss means the root-set scan missed a reference, and
    the compilation must halt because scanFallibility would
    have skipped that module's error registration.
**/
class RustEmissionPlan {
    /**
        Synthetic-impl modules that are referenced from emitted
        bodies.  Key: module path (same key as
        RustEmissionState.referencedImpls).
    **/
    public var referencedImplModules:Map<String, Bool> = [];

    /**
        Private static functions that have a reference recorded
        by scanStaticReferences.  Key: "module.fieldName".
        Only private (non-public, non-test, non-exception)
        statics need an entry; shouldEmitStaticField returns
        true unconditionally for every other kind.
    **/
    public var fieldEmit:Map<String, Bool> = [];

    public function new() {}

    /**
        Returns true when the synthetic-impl module is
        referenced from emitted bodies (pre-computed at plan
        construction).
    **/
    public function isImplModuleReferenced(module:String):Bool {
        return referencedImplModules.exists(module);
    }

    /**
        Returns true when a static field emits.  `isStatic` is
        the caller's original emission-time view of the field,
        passed through so the constructor (which scanFallibility
        walks with isStatic=false) keeps emitting exactly as the
        former inline gate did.
        Instance members, public statics, @:test statics,
        and exception-subclass statics always emit.
        Private statics emit only when fieldEmit records a
        reference found by scanStaticReferences.
    **/
    public function shouldEmitStaticField(cls:ClassType, field:ClassField, isStatic:Bool):Bool {
        if (!isStatic)
            return true;
        if (field.isPublic || field.meta.has(":test"))
            return true;
        if (RustDecl.isExceptionSubclass(cls))
            return true;
        return fieldEmit.exists(cls.module + "." + field.name);
    }

    /**
        Asserts that every render-time write to
        state.referencedImpls was already predicted by the
        body-walk that populated referencedImplModules.
        Called at the start of generateFilesManually, after
        all rendering is done.
    **/
    public function assertReferencedImplsSuperset(renderTime:Map<String, Bool>):Void {
        for (module in renderTime.keys()) {
            if (!referencedImplModules.exists(module)) {
                Context.error(
                    "synthetic impl module '" + module
                    + "' was referenced at render time but not predicted"
                    + " by the emission plan; the pre-scan root-set walk"
                    + " missed a reference",
                    Context.currentPos()
                );
            }
        }
    }
}
#end
