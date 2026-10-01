package varfieldsmartcast;

/** The measured subject: a plain class with a plain method. */
class VarFieldSmartCastMeasurement {
    public var n:Int;
    public function new(v:Int) n = v;
    public function magnitude():Int return n < 0 ? -n : n;
}
