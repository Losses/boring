package boring;

class WhileNullableCond {
    public static function f(flag:Null<Bool>):Int {
        var n = 0;
        var cond = flag;
        while (cond) {
            n++;
            cond = n < 3;
        }
        return n;
    }
}
