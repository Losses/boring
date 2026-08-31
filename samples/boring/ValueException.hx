/**
 * The exception shape the value record sample throws, as ruled in
 * docs/specs/features/06-errors-and-results.md: a haxe.Exception subclass
 * carrying the ValueError variant as failure identity. Constructing the
 * message from the variant keeps the message display text.
 */
package boring;

class ValueException extends haxe.Exception {
	public final error:ValueError;

	public function new(error:ValueError) {
		this.error = error;
		super(ValueException.describe(error));
	}

	public static function describe(error:ValueError):String {
		return switch (error) {
			case StartAfterEnd: "start exceeds end";
			case NegativeStart: "start is negative";
			case BlankValue: "value is blank";
		};
	}
}
