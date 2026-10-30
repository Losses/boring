package rusthandlefixtures;

// interface dispatch: a method is invoked through an interface type.
interface Speaker {
    public function speak():String;
}

class LoudSpeaker implements Speaker {
    public function new() {}

    public function speak():String {
        return "loud";
    }
}

class InterfaceDispatchOps {
    public static function run(speaker:Speaker):String {
        return speaker.speak();
    }
}
