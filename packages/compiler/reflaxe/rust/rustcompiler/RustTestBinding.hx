package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.ClassType;
import RuntimeResidents;
import PolicyQueries;

class RustTestBinding {
    public static function isTestExtern(cls:ClassType):Bool {
        return PolicyQueries.isTestExtern(cls);
    }

    public static function isTestPlatformExtern(module:String):Bool
        return RuntimeResidents.residentOfPlatformExtern(module) == "runtime.TestCore";

    public static function shimModule():String
        return externModules()[0];

    public static function externModules():Array<String>
        return RuntimeResidents.externsOf("runtime.TestCore");

    public static function externModule():String
        return externModules()[0];

    public static function shimPath():String
        return "test.rs";
}
#end
