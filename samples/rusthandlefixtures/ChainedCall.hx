package rusthandlefixtures;

// chained call: field -> clone -> method on a handle.
// Mirrors tiqian width_independent_annotation_cache.rs:852/1442
// ((engine.borrow().fallback_resolver).clone().resolve(...)).
class Resolver {
    public function new() {}

    public function resolve():String {
        return "r";
    }
}

class Engine {
    public final resolver:Resolver;
    public function new(resolver:Resolver) {
        this.resolver = resolver;
    }
}

class ChainedCallOps {
    public static function run(engine:Engine):String {
        return engine.resolver.resolve();
    }
}
