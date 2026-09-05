package boring;

class NoSuchElementFaultException extends haxe.Exception {
    public final fault:NoSuchElementFault;

    public function new(fault:NoSuchElementFault) {
        this.fault = fault;
        super(describe(fault));
    }

    public static function describe(fault:NoSuchElementFault):String {
        return switch (fault) {
            case Missing: "no such element";
        };
    }
}
