package probe;

// An interface parameter reads the same handle-backed class static twice in
// one statement. The emitter binds one cloned read for the whole statement,
// and every read that moves the shared handle must clone the binding again,
// or the second move fails to compile (E0382).
interface OwnershipRole {}

class OwnershipImpl implements OwnershipRole {
    public function new() {}
}

class StaticReadOwnership {
    public static final INSTANCE:OwnershipImpl = new OwnershipImpl();

    public static function same(a:OwnershipRole, b:OwnershipRole):Bool {
        return a == b;
    }

    public static function run():Bool {
        return same(INSTANCE, INSTANCE);
    }
}
