/**
 * Failure identity of the vector codec, shared by every language tree as
 * ruled in docs/specs/features/06-errors-and-results.md. The variant set
 * matches the Rust `VectorError` enum, the TypeScript `VectorError` union,
 * and the Kotlin sealed `VectorException` one to one. Messages are display
 * text derived from the variant; no consumer reads them back.
 */

package boring;

enum VectorError {
    BadMagic;
    CountOverflow;
    UnexpectedEof;
    TrailingBytes(remaining:Int);
}
