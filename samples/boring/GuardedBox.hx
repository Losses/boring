package boring;

#if rust_output
class GuardedBox {
    public var rect:Null<GuardedRect>;

    public function new() {
        rect = null;
    }
}
#else
class GuardedBox {}
#end
