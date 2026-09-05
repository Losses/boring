package boring;

/**
 * Cross-module interface shape: the interface and the consuming static
 * live in this module, the implementing class lives in a second module,
 * and a third module (the test bundle) performs the call whose argument
 * is typed by the interface.
 */
interface TextShaper {
    function shape(text:String):String;
}

class ShapeTextOps {
    public static function render(shaper:TextShaper, text:String):String {
        return shaper.shape(text);
    }
}
