package boring;

class JvmFieldPrivateOps {
    public static var publicTag:Int = 1;

    private static var privateTag:Int = 2;

    @:allow(tests.JvmFieldPrivateTests)
    private static var allowTag:Int = 3;

    public static function resolve():String {
        return privateTag + ":" + publicTag + ":" + allowTag;
    }
}
