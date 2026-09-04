package std;

/**
 * The exception std.UString construction checks throw, following the
 * enum-carrying shape of docs/specs/features/06-errors-and-results.md.
 */
class UStringException extends haxe.Exception {
    public final fault:UStringFault;

    public function new(fault:UStringFault) {
        this.fault = fault;
        super(UStringException.describe(fault));
    }

    public static function describe(fault:UStringFault):String {
        return switch (fault) {
            case InvalidCodePoint(code): 'invalid code point: $code';
            case UnpairedSurrogate(unit): 'unpaired surrogate: $unit';
        };
    }
}
