#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
    Shared private static reachability scan for target emitters. Keeping this
    mechanism in the compiler layer prevents per-target copies from drifting;
    the user ruling of 2026-09-05 places cross-target semantic mechanisms here.
**/
class StaticReferenceScan {
    /** Returns private static method keys referenced by emitted class bodies. */
    public static function scan(mtypes:Array<ModuleType>, inEmissionScope:ClassType->Bool, alwaysKeepClass:ClassType->Bool = null):Map<String, Bool> {
        final candidates:Map<String, TypedExpr> = [];
        final bodies:Array<{e:TypedExpr, candidateKey:Null<String>}> = [];
        function classBodies(c:Ref<ClassType>) {
            final cls = c.get();
            if (!inEmissionScope(cls))
                return;
            for (f in cls.statics.get()) {
                final e = f.expr();
                if (e == null)
                    continue;
                final kept = alwaysKeepClass != null && alwaysKeepClass(cls);
                final prunable = !f.isPublic && !f.meta.has(":test") && !kept && f.kind.match(FMethod(_));
                final key = prunable ? cls.module + "." + f.name : null;
                if (key != null)
                    candidates.set(key, e);
                bodies.push({e: e, candidateKey: key});
            }
            for (f in cls.fields.get()) {
                final e = f.expr();
                if (e != null)
                    bodies.push({e: e, candidateKey: null});
            }
            final ctor = cls.constructor != null ? cls.constructor.get() : null;
            if (ctor != null) {
                final e = ctor.expr();
                if (e != null)
                    bodies.push({e: e, candidateKey: null});
            }
        }
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c):
                    classBodies(c);
                case _:
            }
        }
        final referenced:Map<String, Bool> = [];
        function collectInto(e:TypedExpr) {
            switch (e.expr) {
                case TField(_, FStatic(c, cf)):
                    referenced.set(c.get().module + "." + cf.get().name, true);
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, collectInto);
        }
        for (entry in bodies) {
            if (entry.candidateKey == null)
                collectInto(entry.e);
        }
        var frontier = [for (k in referenced.keys()) k];
        final propagated:Map<String, Bool> = [];
        while (frontier.length > 0) {
            final next:Array<String> = [];
            for (k in frontier) {
                if (!candidates.exists(k) || propagated.exists(k))
                    continue;
                propagated.set(k, true);
                collectInto(candidates.get(k));
                for (k2 in referenced.keys()) {
                    if (!propagated.exists(k2) && candidates.exists(k2))
                        next.push(k2);
                }
            }
            frontier = next;
        }
        final result:Map<String, Bool> = [];
        for (key in candidates.keys())
            if (referenced.exists(key))
                result.set(key, true);
        return result;
    }
}
#end
