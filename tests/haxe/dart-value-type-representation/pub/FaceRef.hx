package pub;

/**
	Marked value type whose `value` accessor is inline: Haxe inlines
	`id.value` into the representation, so a read in a representation
	position must name the extension type's representation field instead of
	the wrapper.
**/
@:valueType
abstract FaceRef(String) {
    public inline function new(value:String)
        this = value;

    public static function of(value:String):FaceRef
        return new FaceRef(value);

    inline function get_value():String
        return this;

    public var value(get, never):String;

    public function toString():String
        return this;
}
