import std.Process;

class ProcessArgsOnly {
    public static function observedValue():Int {
        return Process.args().length;
    }

    static function main():Void {}
}
