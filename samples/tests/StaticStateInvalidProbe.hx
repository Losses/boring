package tests;

class StaticStateInvalidProbe {
    public static var seed:Int = computeBase();

    public static function computeBase():Int {
        return 1;
    }
}
