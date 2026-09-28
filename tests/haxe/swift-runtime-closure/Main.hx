class Main {
    public static function observedValue():Int {
        final owner:Array<Int> = [1];
        final view:std.ReadOnlyArray<Int> = owner;
        owner.push(2);
        final copy = owner.copy();
        return view[1] + owner.length + copy[0];
    }

    static function main():Void {}
}
