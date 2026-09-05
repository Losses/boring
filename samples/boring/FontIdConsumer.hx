package boring;

/**
    Consumer in a second module of the non-inline static on a sub-type
    abstract: `FontId.of` lowers to the abstract implementation's
    companion, so the generated tree must carry the `_Impl_` object.
**/
class FontIdConsumer {
    public static function isPrefixed(face:String):Bool {
        final id:FontId = FontId.of(face);
        return id == "font:hello";
    }
}