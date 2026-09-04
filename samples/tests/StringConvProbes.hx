package tests;

class StringConvProbes {
    public static function negativeValue():String
        return StringTools.hex(-1);

    public static function negativeDigits():String
        return StringTools.hex(1, -1);
}
