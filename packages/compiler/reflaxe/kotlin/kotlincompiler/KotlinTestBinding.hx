package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.ClassType;
import RuntimeResidents;
import PolicyQueries;

class KotlinTestBinding {
    public static function isTestExtern(cls:ClassType):Bool {
        return PolicyQueries.isTestExtern(cls);
    }

    public static function isTestPlatformExtern(module:String):Bool
        return RuntimeResidents.residentOfPlatformExtern(module) == "runtime.TestCore";

    public static function isTestExternModule(module:String, name:String):Bool
        return RuntimeResidents.externsOf("runtime.TestCore").indexOf(module) >= 0
            && (name == "ok" || name == "fail" || StringTools.startsWith(name, "equals"));
}
#end
