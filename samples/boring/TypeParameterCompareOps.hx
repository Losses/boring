package boring;

#if swift_output
/**
    A generic comparison whose operands carry no Equatable constraint, so the
    generated Swift compares the value descriptions.
**/
class TypeParameterCompareOps {
    public static function same<T>(a:T, b:T):Bool
        return a == b;

    public static function different<T>(a:T, b:T):Bool
        return a != b;
}
#else
class TypeParameterCompareOps {}
#end
