package boring;

#if dart_output
class DartCoalesceReceiver {
    public final mode:Int;
    public final kind:Int;

    public function new(?mode:Null<Int>, ?kind:Null<Int>) {
        this.mode = mode == null ? DartCoalesceReceiver.DefaultMode : mode;
        this.kind = kind == null ? DartCoalesceKind.DefaultKind : kind;
    }

    public static final DefaultMode:Int = 7;

    public static final partial:DartCoalesceReceiver = new DartCoalesceReceiver(2, null);

    public static final preset:DartCoalesceReceiver = new DartCoalesceReceiver();
}
#end
