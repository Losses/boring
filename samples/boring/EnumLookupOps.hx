package boring;

#if swift_output
/**
    `Type.createEnum`/`Type.enumConstructor` round-trip: the failable
    raw-value initializer unwraps before the name read.
*/
enum ShapeSource {
    Stub;
    Skia;
    CoreText;
}

class EnumLookupOps {
    public static function roundTrip(name:String):String
        return Type.enumConstructor(Type.createEnum(ShapeSource, name));
}
#else
class EnumLookupOps {}
#end
