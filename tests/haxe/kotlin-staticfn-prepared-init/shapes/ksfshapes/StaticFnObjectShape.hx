package ksfshapes;

/** The all-static shape: every member is static, so the Kotlin output is an
    object declaration and the function-typed var takes the objectVarDecl
    branch of staticFunctionVarDecl. **/
class StaticFnObjectShape {
    public static var shaped:String->String = function(value:String):String {
        var doubled = value + value;
        var tagged = "[" + doubled + "]";
        return tagged;
    };

    public static function apply(value:String):String {
        return shaped(value);
    }
}
