package boring

/**
 * Failure identity of the vector codec, shared by every language tree as
 * ruled in docs/specs/features/06-errors-and-results.md. The variant set
 * matches the Rust `VectorError` enum, the TypeScript `VectorError` union,
 * and the Haxe `VectorError` enum one to one. Messages are display text
 * derived from the variant; no consumer reads them back.
 */
sealed class VectorException(message: String) : RuntimeException(message) {
    data object BadMagic : VectorException("bad vector magic")
    data object CountOverflow : VectorException("record count exceeds u32")
    data object UnexpectedEof : VectorException("vector ended mid-record")
    data class TrailingBytes(val remaining: Int) :
        VectorException("trailing bytes in vector: $remaining")
}
