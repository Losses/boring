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
        if (!probeEnvInheritance()) {
            return false;
        }
        final path = Process.cwd() + "/boring-process-probe.txt";
        Fs.writeText(path, "working");
        Fs.deleteFile(path);
        if (Fs.exists(path)) {
            return false;
        }
        final source = Process.cwd() + "/boring-process-probe-source.txt";
        Fs.writeText(source, "new content");
        Fs.writeText(path, "old content");
        Fs.rename(source, path);
        final replaced = !Fs.exists(source) && Fs.readText(path) == "new content";
        Fs.deleteFile(path);
        return replaced && !Fs.exists(path);
    }

    /** The env-inheritance half of the probe. A POSIX host reads the
        variable through printenv; a Windows host has no such program, so
        it reads it through the cmd shell builtin. Either way the child must
        see the variable passed in the spawn environment - that is the
        behaviour under test; the program choice is incidental. (PortableEnvProbe) */
    static function probeEnvInheritance():Bool {
        final windows = Process.platform() == "windows";
        final result = windows
            ? Process.run("cmd", ["/c", "echo %BORING_PROCESS_PROBE%"], Process.cwd(), [
                {name: "BORING_PROCESS_PROBE", value: "working"}
            ])
            : Process.run("printenv", ["BORING_PROCESS_PROBE"], Process.cwd(), [
                {name: "BORING_PROCESS_PROBE", value: "working"}
            ]);
        return result.code == 0 && StringTools.trim(result.stdout) == "working" && StringTools.trim(result.stderr) == "";
    }

    public static function consoleProbe():Void {
        Console.log("boring stdout probe");
        Console.error("boring stderr probe");
    }
}
