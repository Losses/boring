package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
    Tracks the runtime-package references of one generated file. The
    Swift target emits every module into one Swift module, so cross-module
    references need no import statements; what remains of the import
    table is the runtime-usage flag that gates Runtime.swift emission
    and the resident-purity rule of RuntimeResidents.
**/
class SwiftImports {
    public final selfModule:String;
    public final selfResident:Bool;

    var needsFoundation:Bool = false;
    final runtimeNames:Map<String, Bool> = [];
    final runtimeTestNames:Map<String, Bool> = [];

    public function new(selfModule:String) {
        this.selfModule = selfModule;
        this.selfResident = RuntimeResidents.isResident(selfModule);
    }

    /**
        Records a runtime-symbol reference. The runtime-import define is
        only consulted for targets that import the runtime package; Swift
        links it as one module with the business tree.
    **/
    public function runtime(name:String):Void {
        if (selfResident) {
            // Resident modules append into Runtime.swift itself; a
            // runtime reference from one resolves in the same module.
            return;
        }
        runtimeNames.set(name, true);
    }

    /** Records use of APIs supplied by Foundation. */
    public function foundation():Void {
        needsFoundation = true;
    }

    public function usesFoundation():Bool {
        return needsFoundation;
    }

    /** Records a reference to a symbol of the test host entry. */
    public function runtimeTest(name:String):Void {
        runtimeTestNames.set(name, true);
    }

    /** Whether any runtime symbol was referenced from this module. */
    public function usesRuntime():Bool {
        return hasAnyKey(runtimeNames) || hasAnyKey(runtimeTestNames);
    }

    /** Whether any test-host symbol was referenced. */
    public function usesRuntimeTest():Bool {
        return hasAnyKey(runtimeTestNames);
    }

    /**
        Value and type references between business modules resolve inside
        the one Swift module without imports; the check that remains is
        the resident-purity rule: the runtime package must not depend on
        generated business modules.
    **/
    public function value(module:String, name:String):Void {
        checkPurity(module);
    }

    public function type(module:String, name:String):Void {
        checkPurity(module);
    }

    function checkPurity(module:String):Void {
        if (module == selfModule || module == "Math" || module == "String" || module == "Std" || RuntimeResidents.isResident(module)) {
            return;
        }
        if (selfResident) {
            Context.error("resident runtime module "
                + selfModule
                + " references "
                + module
                + "; the runtime package must not depend on generated business modules",
                Context.currentPos());
        }
    }

    static function hasAnyKey(map:Map<String, Bool>):Bool {
        for (_ in map.keys()) {
            return true;
        }
        return false;
    }
}
#end
