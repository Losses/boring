package boring;

class NoSuchElementFaultException extends haxe.Exception {
    public final fault:NoSuchElementFault;

    public function new(fault:NoSuchElementFault) {
        this.fault = fault;
        super(describe(fault));
    }

    // The parameter keeps the legacy call shape; the switch over the
    // single-case fault folds to a constant, so the name carries the
    // unused-argument marker the generated targets lint for.
    public static function describe(_fault:NoSuchElementFault):String {
        return switch (_fault) {
            case Missing: "no such element";
        };
    }
}
