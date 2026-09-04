// expect: V04 UntypedThrow
class Case {
    static function main():Void {
        throw new haxe.Exception("codec failed");
    }
}
