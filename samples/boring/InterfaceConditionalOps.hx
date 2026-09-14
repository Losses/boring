package boring;

#if rust_output
/**
    A conditional result whose declared type is an interface while each arm
    constructs a concrete implementor. The result slot boxes every concrete
    arm. The named interfaceConditionalBranch rule covers the position.
*/
interface ChoiceText {
    function text():String;
}

class ChoiceAlpha implements ChoiceText {
    public function new() {}

    public function text():String {
        return "alpha";
    }
}

class ChoiceBeta implements ChoiceText {
    public function new() {}

    public function text():String {
        return "beta";
    }
}

class InterfaceConditionalOps {
    public static function choose(flag:Bool):ChoiceText {
        return if (flag) new ChoiceAlpha() else new ChoiceBeta();
    }

    public static function chooseText(flag:Bool):String {
        return choose(flag).text();
    }
}
#else
class InterfaceConditionalOps {}
#end
