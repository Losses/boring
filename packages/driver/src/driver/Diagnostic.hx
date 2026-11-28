package driver;

class Diagnostic {
    public static function describe(fault:DriverFault):String {
        return switch (fault) {
            case InvalidConfig(message): message;
            case Unsupported(message): message;
            // The translated fault enum gains one variant per module that
            // parses generated arguments, so the switch keeps a wildcard to
            // stay total there.
            case _: "driver fault";
        };
    }
}
