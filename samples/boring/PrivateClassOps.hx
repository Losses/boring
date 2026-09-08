package boring;

class PrivateClassOps {
    public static function resolve():String {
#if kotlin_output
        return new Resolution("first").value;
#else
        return new ResolutionOne("first").value;
#end
    }
}

#if kotlin_output
private class Resolution {
#else
private class ResolutionOne {
#end
    public final value:String;

    public function new(value:String) {
        this.value = value;
    }
}
