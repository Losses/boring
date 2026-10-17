import std.Fs;

class FsReadDirOnly {
    public static function observedValue():Int {
        final names = Fs.readDir("/tmp/tq-swift-readdir-fixture");
        return names.length;
    }

    static function main():Void {}
}
