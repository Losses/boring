package comparisonplan;

class IdentityRuntimeMain {
    static function sameReference(left:IdentityReference, right:IdentityReference):Bool {
        return left == right;
    }

    static function sameNullableReference(left:Null<IdentityReference>, right:Null<IdentityReference>):Bool {
        return left == right;
    }

    public static function run():String {
        var shared:IdentityReference = new IdentityReference();
        var distinct:IdentityReference = new IdentityReference();
        var same:Null<IdentityReference> = shared;
        var sameAgain:Null<IdentityReference> = shared;
        var other:Null<IdentityReference> = distinct;
        var absent:Null<IdentityReference> = null;
        return "plain=" + sameReference(shared, shared)
            + ";distinct=" + sameReference(shared, distinct)
            + ";nullableSame=" + sameNullableReference(same, sameAgain)
            + ";nullableDistinct=" + sameNullableReference(same, other)
            + ";nilNil=" + sameNullableReference(absent, null)
            + ";nilPresent=" + sameNullableReference(absent, same);
    }
}
