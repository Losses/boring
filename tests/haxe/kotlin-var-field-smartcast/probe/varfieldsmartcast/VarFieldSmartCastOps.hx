package varfieldsmartcast;

/**
    The var-property smart-cast probe: a nullable class *var* property read
    after a null guard. Kotlin does not smart-cast a mutable property, so the
    generated read must keep its force extraction (`!!`) even though the guard
    proves the value present. Commit 8214566d ("fix(kotlin): keep force
    extraction on var-property null-narrowing") added the guard for exactly
    this shape on the ci/collected-suite-failure-attribution lineage (it is
    not on the arch/agent-guided-governance base); nothing in either tree pins
    it, which is how a merge could drop
    it silently. (VarFieldSmartCast)
**/
class VarFieldSmartCastOps {
    /** Read a nullable var property after a null guard: needs `!!`. */
    public static function readThroughVar(holder:VarFieldSmartCastHolder):Int {
        if (holder.value != null)
            return holder.value.magnitude();
        return -1;
    }

    /** The val-side control: a final property of the same shape. */
    public static function readThroughVal(holder:VarFieldSmartCastFinalHolder):Int {
        if (holder.value != null)
            return holder.value.magnitude();
        return -1;
    }
}
