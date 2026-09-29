package ksfshapes;

/**
    Regression shapes for the static function-field initializer repair.
    The instance member keeps StaticFnShapes on the companion-object branch
    of staticFunctionVarDecl; StaticFnObjectShape is all static and takes
    the object branch.
**/
class StaticFnShapes {
    public var stamp:Int;

    public function new() {
        stamp = 0;
    }

    public static var shaped:String->String = function(value:String):String {
        var opened = value + "<";
        var closed = opened + ">";
        return closed;
    };

    public static var nullable:String->Null<String> = function(value:String):Null<String> {
        var probe:String->Null<String> = function(input:String):Null<String> {
            if (input == "") {
                return null;
            }
            return input;
        };
        var raised = probe(value);
        if (raised == null) {
            return null;
        }
        return raised + "!";
    };

    public static function applyShaped(value:String):String {
        return shaped(value);
    }

    public static function applyNullable(value:String):Null<String> {
        return nullable(value);
    }
}