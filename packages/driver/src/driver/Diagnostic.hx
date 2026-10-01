package driver;

class Diagnostic {
    public static function describe(fault:DriverFault):String {
        return switch (fault) {
            case InvalidConfig(message): message;
        };
    }
}
