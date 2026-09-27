package driver;

#if js
import js.Syntax;
#end

typedef HostResult = {
    code:Int,
    output:String
};

/** Host operations used by the delivered command. */
class Host {
    public static function exists(path:String):Bool {
        #if js
        return Syntax.code("require('fs').existsSync({0})", path);
        #else
        return std.Fs.exists(path);
        #end
    }

    public static function readText(path:String):String {
        #if js
        return Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
        #else
        return std.Fs.readText(path);
        #end
    }

    public static function writeText(path:String, contents:String):Void {
        #if js
        Syntax.code("require('fs').writeFileSync({0}, {1})", path, contents);
        #else
        std.Fs.writeText(path, contents);
        #end
    }

    public static function rename(from:String, to:String):Void {
        #if js
        Syntax.code("require('fs').renameSync({0}, {1})", from, to);
        #else
        std.Fs.rename(from, to);
        #end
    }

    public static function makeDirs(path:String):Void {
        #if js
        Syntax.code("require('fs').mkdirSync({0}, {recursive: true})", path);
        #else
        std.Fs.makeDirs(path);
        #end
    }

    public static function deleteFile(path:String):Void {
        if (!exists(path)) return;
        #if js
        Syntax.code("require('fs').rmSync({0}, {force: true})", path);
        #else
        std.Fs.deleteFile(path);
        #end
    }

    public static function readDir(path:String):Array<String> {
        #if js
        return Syntax.code("require('fs').readdirSync({0})", path);
        #else
        return std.Fs.readDir(path);
        #end
    }

    public static function isDirectory(path:String):Bool {
        #if js
        return Syntax.code("require('fs').statSync({0}).isDirectory()", path);
        #else
        return std.Fs.isDirectory(path);
        #end
    }

    public static function join(a:String, b:String):String {
        #if js
        return Syntax.code("require('path').join({0}, {1})", a, b);
        #else
        return std.Path.join(a, b);
        #end
    }

    public static function resolve(base:String, relative:String):String {
        #if js
        return Syntax.code("require('path').resolve({0}, {1})", base, relative);
        #else
        return std.Path.normalize(std.Path.join(base, relative));
        #end
    }

    public static function dirname(location:String):String {
        #if js
        return Syntax.code("require('path').dirname({0})", location);
        #else
        return std.Path.dirname(location);
        #end
    }

    public static function cwd():String {
        #if js
        return Syntax.code("process.cwd()");
        #else
        return std.Process.cwd();
        #end
    }

    public static function args():Array<String> {
        #if js
        return Syntax.code("process.argv.slice(2)");
        #else
        return std.Process.args();
        #end
    }

    public static function platform():String {
        #if js
        return Syntax.code("process.platform");
        #else
        return std.Process.platform();
        #end
    }

    public static function env(name:String):Null<String> {
        #if js
        return Syntax.code("process.env[{0}] || null", name);
        #else
        return std.Env.get(name);
        #end
    }

    public static function outputLine(message:String):Void {
        #if js
        Syntax.code("process.stdout.write({0} + '\\n')", message);
        #else
        std.Console.log(message);
        #end
    }

    public static function printError(message:String):Void {
        #if js
        Syntax.code("process.stderr.write({0} + '\\n')", message);
        #else
        std.Console.error(message);
        #end
    }

    public static function exit(code:Int):Void {
        #if js
        Syntax.code("process.exit({0})", code);
        #else
        std.Process.exit(code);
        #end
    }

    public static function run(command:String, args:Array<String>, cwd:String, extra:Array<EnvVar>):HostResult {
        #if js
        final env:Dynamic = Syntax.code("({...process.env})");
        for (entry in extra) Reflect.setField(env, entry.key, entry.value);
        final proc:Dynamic = Syntax.code(
            "require('child_process').spawnSync({0}, {1}, {cwd: {2}, env: {3}, encoding: 'utf8', maxBuffer: 1024 * 1024 * 64})",
            command, args, cwd, env);
        if (proc.error != null) return {code: -1, output: Std.string(proc.error)};
        final code = proc.status == null ? -1 : (proc.status:Int);
        return {code: code, output: (proc.stdout == null ? "" : proc.stdout) + (proc.stderr == null ? "" : proc.stderr)};
        #else
        final values:Array<std.Process.ProcessEnv> = [];
        for (entry in extra) values.push({name: entry.key, value: entry.value});
        final result = std.Process.run(command, args, cwd, values);
        return {code: result.code, output: result.stdout + result.stderr};
        #end
    }
}
