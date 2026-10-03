package boring;

#if ts_output
/**
    `Type.createEnum`/`Type.enumConstructor` round-trip for TS QName nullable
    unwrap: the `*OfName` lookup returns a nullable, and the `.kind` read on
    it must assert non-null (`!.kind`) to satisfy the strict type checker.
*/
enum R42ShapeTag {
    Alpha;
    Beta;
}

class EnumQNameNullPreservingFixture {
    public static function kindOfLookup(name:String):String
        return Type.enumConstructor(Type.createEnum(R42ShapeTag, name));

    public static function kindOfValue(tag:R42ShapeTag):String
        return Type.enumConstructor(tag);

    public static function kindOfCoalesce(maybe:Null<R42ShapeTag>):String
        return Type.enumConstructor(if (maybe == null) R42ShapeTag.Alpha else maybe);
}
#else
class EnumQNameNullPreservingFixture {}
#end
