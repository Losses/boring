// expect: V01 IteratorLoop
class Case {
    static function main():Void {
        final items:Iterable<Int> = new Array<Int>();
        for (item in items) {
            trace(item);
        }
    }
}
