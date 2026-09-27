package boring;

import std.Process;
import std.Process.ProcessEnv;
import std.Fs;
import std.Console;

class ProcessOps {
    public static function run(command:String, args:Array<String>, cwd:String, env:Array<ProcessEnv>):String {
        final result = Process.run(command, args, cwd, env);
        return result.code + ":" + result.stdout + ":" + result.stderr;
    }

    public static function cwd():String {
        return Process.cwd();
    }

    public static function hostProbe():Bool {
        final result = Process.run("printenv", ["BORING_PROCESS_PROBE"], Process.cwd(), [
            {name: "BORING_PROCESS_PROBE", value: "working"}
        ]);
        if (result.code != 0 || result.stdout != "working\n" || result.stderr != "") {
            return false;
        }
        final path = Process.cwd() + "/boring-process-probe.txt";
        Fs.writeText(path, "working");
        Fs.deleteFile(path);
        return !Fs.exists(path);
    }

    public static function consoleProbe():Void {
        Console.log("boring stdout probe");
        Console.error("boring stderr probe");
    }
}
