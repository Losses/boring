package boring;

enum PayloadSelfMapError {
    Missing;
}

@:dataClass
class PayloadSelfMapException {
    public final error:PayloadSelfMapError;
    public final message:String;

    public function new(error:PayloadSelfMapError) {
        this.error = error;
        this.message = "payload self-map";
    }

    public static function make():PayloadSelfMapException {
        return new PayloadSelfMapException(PayloadSelfMapError.Missing);
    }
}
