package boring;

class DartEmptyArrayFixOps {
    public static function emptyArrayArgument():Int {
#if dart_output
        return new DartEmptyArrayFixOptional().count();
#else
        return 0;
#end
    }
}

#if dart_output
class DartEmptyArrayFixOptional {
    final values:std.ReadOnlyArray<String>;

    public function new(?values:std.ReadOnlyArray<String>) {
        this.values = values == null ? [] : values;
    }

    public function count():Int {
        return values.length;
    }
}
#end
