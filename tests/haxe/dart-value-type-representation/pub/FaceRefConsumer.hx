package pub;

/** Passes an inlined representation read where a String is demanded. */
class FaceRefConsumer {
    public static function describe(ref:FaceRef):String
        return label(ref.value);

    static function label(value:String):String
        return "[" + value + "]";
}
