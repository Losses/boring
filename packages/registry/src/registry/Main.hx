package registry;

import std.Fs;
import std.Path;
import std.Process;
import registry.Core.InputRecord;

class Main {
    static function readTree(root:String, rel:String, out:Array<InputRecord>):Void {
        var full = rel == "" ? root : Path.join(root, rel);
        if (Fs.isDirectory(full)) {
            var names = Fs.readDir(full);
            for (j in 0...names.length) {
                var name = names[j];
                readTree(root, rel == "" ? name : rel + "/" + name, out);
            }
        } else
            out.push({path: rel, content: Fs.readText(full), inputRecord: 1});
    }

    /** The repository generator entry: reads the tree and writes the
        site. Failures raise the haxe.Exception mapping; the caller (the
        CLI host or a test) reports them. */
    public static function main():Void {
        var config = Core.parseArgs(Process.args());
        if (Fs.exists(config.output) && Fs.readDir(config.output).length > 0)
            throw new CoreException(Config("output directory is not empty"));
        var records:Array<InputRecord> = [];
        if (!Fs.exists(config.tree))
            throw new CoreException(Config(config.tree + ": missing tree"));
        readTree(config.tree, "", records);
        var files = Core.generate(records, config);
        for (j in 0...files.length) {
            var file = files[j];
            var p = Path.join(config.output, file.path);
            Fs.makeDirs(Path.dirname(p));
            Fs.writeText(p, file.content);
        }
    }
}
