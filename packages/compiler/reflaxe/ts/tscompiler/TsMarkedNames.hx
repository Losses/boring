package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import PolicyQueries;
import RuntimeResidents;
import StaticFunctionMarkers;
import ValueTypeSupport;

/**
    Emitted-name resolution for marked statics (features/10) whose natural name
    at module scope is claimed by more than one declaring class in one Haxe
    module. TypeScript gives a module file one namespace, so two
    `export function f` declarations collide (TS2323/TS2393); the class
    qualifier is the only thing that still tells the declarations apart. P-21
    rules the target family: a legal natural name wins and every other
    claimant mangles deterministically, the mangle being the declaring class
    name plus the member name -- the member-qualified spelling the Rust target
    already uses for the inherent-impl form. Declaration and reference resolve
    through one function, so a call site and its declaration always agree.
**/
class TsMarkedNames {
    static final contestedKeys:Map<String, Bool> = [];
    static final naturalOwners:Map<String, String> = [];

    /**
        Pre-scan every emitted class before lowering and record the names
        at module scope that more than one class claims.
    **/
    public static function scan(moduleTypes:Array<ModuleType>):Void {
        final ownersByKey:Map<String, Array<String>> = [];
        final moduleNaturalOwner:Map<String, String> = [];
        for (mt in moduleTypes) {
            switch (mt) {
                case TClassDecl(clsRef):
                    final cls = clsRef.get();
                    if (!emits(cls))
                        continue;
                    final marked = [for (f in cls.statics.get()) if (StaticFunctionMarkers.isMarked(f)) f.name];
                    if (marked.length == 0)
                        continue;
                    // The module's file-named type is the natural owner of the
                    // bare name when it declares it.
                    if (moduleBase(cls.module) == cls.name)
                        moduleNaturalOwner.set(cls.module, cls.name);
                    for (name in marked) {
                        final key = cls.module + "::" + name;
                        var owners = ownersByKey.get(key);
                        if (owners == null)
                            owners = [];
                        if (owners.indexOf(cls.name) < 0)
                            owners.push(cls.name);
                        ownersByKey.set(key, owners);
                    }
                default:
            }
        }
        for (key in ownersByKey.keys()) {
            final owners = ownersByKey.get(key);
            if (owners == null || owners.length < 2)
                continue;
            owners.sort(Reflect.compare);
            final module = key.substr(0, key.lastIndexOf("::"));
            var winner = moduleNaturalOwner.get(module);
            if (winner == null || owners.indexOf(winner) < 0)
                winner = owners[0];
            contestedKeys.set(key, true);
            naturalOwners.set(key, winner);
        }
    }

    /**
        The emitted name of one marked static at module scope: the natural member
        name while the module's marked names are unique, the declaring class
        name plus the member name for every claimant but the natural owner once
        two classes claim the same name.
    **/
    public static function emittedName(module:String, owner:String, name:String):String {
        final key = module + "::" + name;
        if (!contestedKeys.exists(key))
            return name;
        return naturalOwners.get(key) == owner ? name : owner + "_" + name;
    }

    /** Whether one class reaches the emitted tree, mirroring compileClassImpl. */
    static function emits(cls:ClassType):Bool {
        if (cls.isExtern || cls.isInterface)
            return false;
        if (ValueTypeSupport.infoOfClass(cls) != null)
            return false;
        return RuntimeResidents.isResident(cls.module)
            || TsImports.isGuaranteedStdModule(cls.module)
            || PolicyQueries.inSourceScope(cls.pos);
    }

    static function moduleBase(module:String):String {
        final dot = module.lastIndexOf(".");
        return dot < 0 ? module : module.substr(dot + 1);
    }
}
#end
