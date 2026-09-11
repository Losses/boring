package boring;

#if swift_output
class AccessTarget {
    final secret:Int;

    public function new(secret:Int) {
        this.secret = secret;
    }

    function readSecret():Int {
        return secret;
    }
}
#else
class AccessTarget {}
#end
