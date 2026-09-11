package boring;

#if swift_output
class NullGuardNarrowHolder {
    public final index:Null<Int>;

    public function new(index:Null<Int>) {
        this.index = index;
    }
}
#else
class NullGuardNarrowHolder {}
#end
