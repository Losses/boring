package cases;

@:dataClass
class RecursiveKey {
    public final value:Int;
    public final next:Null<RecursiveKey>;

    public function new(value:Int, next:Null<RecursiveKey>) {
        this.value = value;
        this.next = next;
    }
}

class ComparisonCases {
    public static function main():Void {}
}
