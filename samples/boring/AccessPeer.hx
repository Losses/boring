package boring;

#if swift_output
@:access(boring.AccessTarget)
class AccessPeer {
    final target:AccessTarget;

    public function new(target:AccessTarget) {
        this.target = target;
    }

    public function readThrough():Int {
        return target.readSecret() + target.secret;
    }
}
#else
class AccessPeer {}
#end
