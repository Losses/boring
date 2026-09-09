package boring;

/**
 * A value wrapper whose representation parameter shares its name with a
 * member function, plus a clash-free control wrapper. The colliding member
 * is inline so targets that cannot hold a method beside the stored field
 * keep compiling; the Dart backend still renders the member and must rename
 * the extension type representation field instead. Runtime tests reach the
 * representation through the non-inline members below.
 */
@:valueType
abstract ClashCount(Float) from Float {
    public inline function new(count:Float)
        this = count;

    public inline function count():Float
        return this;

    public function doubled():Float
        return this * 2.0;
}

@:valueType
abstract PlainCount(Float) from Float {
    public inline function new(value:Float)
        this = value;

    public function read():Float
        return this;
}
