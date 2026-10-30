package rusthandlefixtures;

// borrowed param: a handle passed to a static function and reused after the
// call, so it must be borrowed rather than moved.
class BorrowedParam {
    public function new() {}
}

class BorrowedParamOps {
    public static function peek(value:BorrowedParam):Int {
        return 1;
    }

    public static function run():Int {
        final value = new BorrowedParam();
        final a = peek(value);
        final b = peek(value);
        return a + b;
    }
}
