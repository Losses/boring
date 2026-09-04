/**
 * The only exception shape codec code throws, as ruled in
 * docs/specs/features/06-errors-and-results.md: a haxe.Exception subclass
 * carrying the VectorError variant as failure identity. Constructing the
 * message from the variant keeps the message display text.
 */

package boring;

class VectorException extends haxe.Exception {
    public final error:VectorError;

    public function new(error:VectorError) {
        this.error = error;
        super(VectorException.describe(error));
    }

    public static function describe(error:VectorError):String {
        return switch (error) {
            case BadMagic: "bad vector magic";
            case CountOverflow: "record count exceeds u32";
            case UnexpectedEof: "vector ended mid-record";
            case TrailingBytes(remaining): 'trailing bytes in vector: $remaining';
        };
    }
}
