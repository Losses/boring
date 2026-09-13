package boring;

import std.StringBuf;

/**
 * StringBuf mutations inside a function whose declared failure identity is a
 * synthetic union: the buffer guard reports UnpairedSurrogate through
 * std.UStringException, while a separate vector path reports VectorError.
 * The rust lowering must wrap the buffer fault in the union variant exactly
 * like an explicit throw (stdlib/08, features/06).
 */
class StringBufUnionOps {
    /** The addChar guard and the vector throw share the returned fault. */
    public static function buildCharChecked(count:Int):String {
        if (count == 0)
            throw new VectorException(VectorError.BadMagic);
        final buf = new StringBuf();
        buf.addChar(0x41);
        return buf.toString();
    }

    /** The add guard and the vector throw share the returned fault. */
    public static function buildChecked(count:Int):String {
        if (count == 0)
            throw new VectorException(VectorError.UnexpectedEof);
        final buf = new StringBuf();
        buf.add("item");
        return buf.toString();
    }
}