package rusthandlefixtures;

// new receiver: a freshly constructed object is the method receiver.
class NewReceiver {
    public function new() {}

    public function label():String {
        return "new";
    }
}

class NewReceiverOps {
    public static function run():String {
        return new NewReceiver().label();
    }
}
