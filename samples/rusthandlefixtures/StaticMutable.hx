package rusthandlefixtures;

// static mutable: a mutable static var holding a handle.
// Mirrors tiqian test_trace_recorder.rs (self stored into a static).
class Config {
    public function new() {}
}

class StaticMutableOps {
    public static var current:Null<Config> = null;

    public static function install(config:Config):Void {
        current = config;
    }

    public static function read():Int {
        return current == null ? 0 : 1;
    }
}
