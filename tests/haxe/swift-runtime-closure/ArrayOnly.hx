class ArrayOnly {
    public static function observedValue():Int {
        final values = new Array<Int>();
        values.push(1);
        values.push(2);
        final copy = values.copy();
        return copy[1] + values.length;
    }

    static function main():Void {}
}
