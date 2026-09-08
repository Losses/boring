package boring;

class PrivateClassPeerOps {
    public static function resolve():String {
#if kotlin_output
        return new Resolution("second").value;
#else
        return new ResolutionTwo("second").value;
#end
    }
}

#if kotlin_output
private class Resolution {
#else
private class ResolutionTwo {
#end
    public final value:String;

    public function new(value:String) {
        this.value = value;
    }
}
