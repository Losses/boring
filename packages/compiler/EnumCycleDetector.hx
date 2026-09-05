#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;

/** Detects cycles in payload-enum argument type graphs. */
class EnumCycleDetector {
    static final cache:Map<String, Bool> = [];

    public static function isCyclic(en:EnumType):Bool {
        final key = en.module + ":" + en.name;
        final known = cache.get(key);
        if (known != null)
            return known;
        // Marking an enum while it is being explored prevents recursive queries.
        final visiting:Map<String, Bool> = [];
        final result = reaches(en, en, visiting);
        cache.set(key, result);
        return result;
    }

    static function reaches(root:EnumType, current:EnumType, visiting:Map<String, Bool>):Bool {
        final key = current.module + ":" + current.name;
        if (visiting.exists(key))
            return same(current, root);
        visiting.set(key, true);
        for (ctor in current.constructs) {
            switch (ctor.type) {
                case TFun(args, _):
                    for (arg in args)
                        if (typeReaches(root, arg.t, visiting))
                            return true;
                case _:
            }
        }
        return false;
    }

    static function typeReaches(root:EnumType, type:Type, visiting:Map<String, Bool>, depth:Int = 0):Bool {
        if (depth > 64)
            return false;
        return switch (Context.follow(type)) {
            case TAbstract(a, params):
                final abs = a.get();
                if (abs.name == "Null" && params.length == 1) typeReaches(root, params[0], visiting, depth + 1) else false;
            case TEnum(e, _): final target = e.get(); same(target, root) || reaches(root, target, visiting);
            case TInst(c, params):
                final cls = c.get();
                if (cls.name == "Array" || cls.module == "std.ReadOnlyArray" || cls.module == "std.SortedSet") params.length == 1
                    && typeReaches(root, params[0], visiting,
                        depth + 1) else if (cls.module == "std.SortedMap") params.length == 2
                    && (typeReaches(root, params[0], visiting, depth + 1) || typeReaches(root, params[1], visiting, depth + 1)) else false;
            case _: false;
        };
    }

    static inline function same(a:EnumType, b:EnumType):Bool
        return a.module == b.module && a.name == b.name;
}
#end
