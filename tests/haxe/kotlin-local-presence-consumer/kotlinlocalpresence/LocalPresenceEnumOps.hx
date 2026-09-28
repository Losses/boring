package kotlinlocalpresence;

enum LocalPresenceChoice {
    First;
    Second;
}

enum LocalPresencePayloadChoice {
    Text(value:String);
    Count(value:Int);
}

class LocalPresenceEnumOps {
    public static function firstMember(choice:LocalPresenceChoice):String {
        return switch (choice) {
            case First: "first";
            case Second: "second";
        };
    }

    public static function secondMember(choice:LocalPresenceChoice):String {
        return switch (choice) {
            case First: "first-again";
            case Second: "second-again";
        };
    }

    public static function firstPayloadMember(choice:LocalPresencePayloadChoice):String {
        return switch (choice) {
            case Text(value): value;
            case Count(value): Std.string(value);
        };
    }

    public static function secondPayloadMember(choice:LocalPresencePayloadChoice):String {
        return switch (choice) {
            case Text(value): "again-" + value;
            case Count(value): "again-" + Std.string(value);
        };
    }
}
