package boring;

#if swift_output
class OptionalValueUseHolder {
    public final value:Int;

    public function new(value:Int) {
        this.value = value;
    }
}
#else
class OptionalValueUseHolder {}
#end
