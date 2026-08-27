package boring

sealed class VectorException(message: String) : RuntimeException(message) {
    data object BadMagic : VectorException("bad vector magic")
    data object CountOverflow : VectorException("record count exceeds u32")
    data object UnexpectedEof : VectorException("vector ended mid-record")
    data class TrailingBytes(val remaining: Int) :
        VectorException("trailing bytes in vector: $remaining")
}
