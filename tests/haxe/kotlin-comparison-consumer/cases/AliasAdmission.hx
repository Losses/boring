package cases;

typedef RecursiveAlias = Null<AliasNode>;

@:dataClass
class AliasNode {
    public final value:Int;
    public final next:RecursiveAlias;

    public function new(value:Int, next:RecursiveAlias) {
        this.value = value;
        this.next = next;
    }
}
