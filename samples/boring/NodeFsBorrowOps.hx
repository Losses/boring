package boring;

#if rust_output
/**
    A node:fs extern lowers to the resident file edge. The resident edge
    takes &str, so a heap String path or payload borrows through as_str at
    the call.
*/
private typedef NodeFsMkdirOptions = {
    final recursive:Bool;
}

@:jsRequire("node:fs")
private extern class NodeFsProbe {
    static function mkdirSync(path:String, options:NodeFsMkdirOptions):Void;
    static function writeFileSync(path:String, text:String, encoding:String):Void;
}

class NodeFsBorrowOps {
    public static function writeProbe(name:String, text:String):String {
        final directory = "target/boring-node-fs-probe";
        NodeFsProbe.mkdirSync(directory, {recursive: true});
        NodeFsProbe.writeFileSync(directory + "/" + name + ".txt", text, "utf8");
        return directory;
    }
}
#else
class NodeFsBorrowOps {}
#end
