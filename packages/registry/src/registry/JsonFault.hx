package registry;

/** Failure identity for the JSON reader, in its own module so the
    Kotlin sealed fold can carry the variants inside JsonException (the
    enum's home module file is intentionally skipped on that target). */
enum JsonFault {
    InvalidJson;
    TrailingInput(position:Int);
}
