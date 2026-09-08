package boring;

#if rust_output
enum PayloadSelfMapError {
    Missing;
}

class PayloadSelfMapException extends haxe.Exception {
    public final error:PayloadSelfMapError;

    public function new(error:PayloadSelfMapError) {
        this.error = error;
        super(describe(error));
    }

    public static function describe(error:PayloadSelfMapError):String {
        return switch (error) {
            case Missing: "payload self-map";
        };
    }

    public static function make():PayloadSelfMapException {
        return new PayloadSelfMapException(PayloadSelfMapError.Missing);
    }
}
#else
enum PayloadSelfMapError {
    Missing;
}

@:dataClass
class PayloadSelfMapException {
    public final error:PayloadSelfMapError;

    public function new(error:PayloadSelfMapError) {
        this.error = error;
    }

    public static function make():PayloadSelfMapException {
        return new PayloadSelfMapException(PayloadSelfMapError.Missing);
    }
}
#end
