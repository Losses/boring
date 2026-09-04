package registry;

import registry.Platform.Fs;
import registry.Platform.NodeProcess;
import registry.Platform.Console;
import registry.Platform.Path;
import registry.Core.InputRecord;

class Main {
    static final USAGE = "usage: generate --tree <dir> --output <site> --base-url <url> [--swift-scope <scope>] [--archive-base <url>]";

    static function readTree(root:String, rel:String, out:Array<InputRecord>):Void {
        var full = rel == "" ? root : Path.join(root, rel);
        if (Fs.statSync(full).isDirectory()) {
            var names = Fs.readdirSync(full);
            for (j in 0...names.length) {
                var name = names[j];
                readTree(root, rel == "" ? name : rel + "/" + name, out);
            }
        } else
            out.push({path: rel, content: Fs.readFileSync(full, "utf8"), inputRecord: 1});
    }

    public static function main():Void {
        try {
            var av = NodeProcess.argv;
            if (av.length == 3 && (av[2] == "--help" || av[2] == "-h")) {
                Console.error(USAGE);
                NodeProcess.exit(0);
            }
            var args:Array<String> = [];
            var i = 2;
            while (i < av.length) {
                args.push(av[i]);
                i = i + 1;
            }
            var config = Core.parseArgs(args);
            if (Fs.existsSync(config.output) && Fs.readdirSync(config.output).length > 0)
                throw new CoreException(Config("output directory is not empty"));
            var records:Array<InputRecord> = [];
            if (!Fs.existsSync(config.tree))
                throw new CoreException(Config(config.tree + ": missing tree"));
            readTree(config.tree, "", records);
            var files = Core.generate(records, config);
            for (j in 0...files.length) {
                var file = files[j];
                var p = Path.join(config.output, file.path);
                Fs.mkdirSync(Path.dirname(p), {recursive: true});
                Fs.writeFileSync(p, file.content, "utf8");
            }
        } catch (e:CoreException) {
            Console.error(e.message);
            NodeProcess.exit(1);
        }
    }
}
