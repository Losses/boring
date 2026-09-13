package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
#end

/**
    Static members a parameter default inlines at call sites. A coalescing
    default such as `?? PrivateHelper.make()` is materialized in the
    caller's class, including call sites in other modules, so the private
    static must widen to Kotlin module visibility. Keyed by the member's
    full path: module + "." + class + "." + member.
**/
class KotlinAccessGrants {
    static final widened:Map<String, Bool> = [];

    public static function widen(key:String):Void {
        widened.set(key, true);
    }

    public static function isWidened(cls:ClassType, fieldName:String):Bool {
        return widened.exists(cls.module + "." + cls.name + "." + fieldName);
    }

    #if (macro || reflaxe_runtime)
    /**
        Pre-emission scan (runs from the compiler's onAfterTyping hook): a
        registered coalescing default names the private statics it may
        inline, and the scan widens exactly those members before the first
        declaration renders, so the widening never depends on class
        emission order.
    **/
    public static function collect(_:Array<ModuleType>):Void {
        DefaultArgExpander.visitDefaultStaticTargets((modulePath, className, methodName) -> {
            if (isPrivateStatic(modulePath, className, methodName)) {
                widen(modulePath + "." + className + "." + methodName);
            }
        });
    }

    static function isPrivateStatic(modulePath:String, className:String, methodName:String):Bool {
        final resolved:Null<Type> = try Context.getType(modulePath + "." + className) catch (_:Dynamic) null;
        return switch (resolved) {
            case TInst(c, _):
                var found = false;
                for (f in c.get().statics.get()) {
                    if (f.name == methodName) {
                        found = !f.isPublic && !f.meta.has(":allow");
                        break;
                    }
                }
                found;
            case _: false;
        };
    }
    #end
}
