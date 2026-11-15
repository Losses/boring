package comparisonplan;

import comparisonplan.IdentityAlias;
import comparisonplan.IdentityReference;

class IdentityFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}

class IdentityMain {
    static function sameNullableAlias(left:Null<IdentityAlias>, right:Null<IdentityAlias>):Bool {
        return left == right;
    }

    static function main():Void {
        var shared:IdentityReference = new IdentityReference();
        var sameThroughAlias:Null<IdentityAlias> = shared;
        var sameAgain:Null<IdentityAlias> = shared;
        var distinct:Null<IdentityAlias> = new IdentityReference();
        if (!sameNullableAlias(sameThroughAlias, sameAgain) || sameNullableAlias(sameThroughAlias, distinct))
            throw new IdentityFault("nullable typedef class equality must preserve reference identity");
    }
}
