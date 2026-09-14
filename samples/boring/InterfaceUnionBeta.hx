package boring;

#if rust_output
import boring.InterfaceUnionOps.InterfaceUnionSlot;

class InterfaceUnionBeta implements InterfaceUnionSlot {
    public function new() {}

    public function run(value:Int):Int {
        if (value == 0)
            throw new ValueException(ValueError.NegativeStart);
        return value;
    }
}
#else
class InterfaceUnionBeta {}
#end
