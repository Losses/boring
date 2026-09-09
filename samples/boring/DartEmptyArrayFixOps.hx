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
    final values:Array<String>;

    public function new(?values:Array<String>) {
        this.values = values;
    }

    public function count():Int {
        return values.length;
    }
}
#end
