package boring;

#if (kotlin_output || ts_output)
import std.Console;

/**
    The standard console object (docs/specs/stdlib/06-std-modules.md) on
    the two engine targets that give it a runtime face: TypeScript binds
    `std.Console.log` to the host console through the extern's
    `@:native` name, and the Kotlin target emits a shim object in the
    runtime package. The extern therefore reaches the Kotlin emitter
    under the native spelling `console` while the shim declares
    `object Console`, so the reference and the declaration must carry
    one spelling. (KotlinConsoleShim)
**/
class ConsoleShimOps {
    /** Write one line and report the call through its result. **/
    public static function logLine(message:String):String {
        Console.log(message);
        return "logged:" + message;
    }
}
#else
class ConsoleShimOps {}
#end
