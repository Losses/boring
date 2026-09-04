// expect: coalesced default expression is not sanctioned
class Case {
    public var field:Int = 1;

    public function new() {}

    static function main()
        new Case().invalid(1);

    public function invalid(first:Int, ?x:Null<Int> = 0):Int {
        final normalized = x == null ? this.field : x;
        return normalized;
    }
}
