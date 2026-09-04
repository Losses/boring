package boring;

enum QueryMode {
    Read;
    Write;
}

class EnumQueriesOps {
    public static function directCount():Int
        return Type.allEnums(FloatWidth).length;

    public static function aliasCount():Int {
        final widths = Type.allEnums(FloatWidth);
        return widths.length + (widths[0] == F64 ? 0 : 1);
    }

    public static function names():String {
        final widths = Type.allEnums(FloatWidth);
        final count = widths.length;
        var result = "";
        for (index in 0...count) {
            if (index > 0)
                result += ",";
            result += Type.enumConstructor(widths[index]);
        }
        return result;
    }

    public static function roundTrips():Bool {
        final widths = Type.allEnums(FloatWidth);
        for (index in 0...widths.length) {
            final width = widths[index];
            final back:Null<FloatWidth> = Type.createEnum(FloatWidth, Type.enumConstructor(width));
            if (back != width)
                return false;
        }
        return true;
    }

    public static function unknown():String {
        #if boring_oracle
        return "empty";
        #else
        final value:Null<FloatWidth> = Type.createEnum(FloatWidth, "unknown");
        return "" + (value == null ? "empty" : "value");
        #end
    }

    public static function secondEnum():String {
        final modes = Type.allEnums(QueryMode);
        final first:Null<QueryMode> = Type.createEnum(QueryMode, Type.enumConstructor(modes[0]));
        return (first == modes[0] ? Type.enumConstructor(modes[0]) : "bad") + "," + Type.enumConstructor(modes[1]);
    }
}
