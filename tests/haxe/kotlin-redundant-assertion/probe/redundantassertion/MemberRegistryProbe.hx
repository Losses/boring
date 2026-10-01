package redundantassertion;

class MemberRegistryInner {
    public var flag:Bool;

    public function new(flag:Bool) this.flag = flag;
}

/**
    The structural control for the finding above.

    The same never-reassigned nullable local is read twice, and the emitter
    already keeps a scope-correct record of "an assertion for this stable
    subject was printed" -- `extractedLocals`, written by `addProofExpr` at the
    emission that actually prints the `!!` (KotlinExpr.hx:2673/:2677), snapshotted
    and restored at every branch, loop, lambda and catch boundary
    (`ExtractionSuppressesRepeat`). Exactly one read site consults it: the
    member-access path (`instanceField`, KotlinExpr.hx:3854 -> :3904).

    So here the second read through the member path drops its assertion on `x`,
    while a bare local operand in a comparison (`operand`, KotlinExpr.hx:3661)
    keeps it. Two read sites, one subject, one rule, two answers -- which is why
    the `isSpace` finding is a missing consultation, and the emitter is able
    to make that proof.
**/
class MemberRegistryProbe {
    public static function localMember(o:Null<MemberRegistryInner>):Bool {
        final x = o;
        final a = x.flag;
        return a && x.flag;
    }
}
