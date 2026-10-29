package org.tiqian.protocol;

/**
 * The JSON-lane wire value, the single-source input of the canonical byte
 * form (ADR 0052). Both platform callers parse their submission into this
 * shape first: the TypeScript caller walks its live JS object, the Rust
 * caller mirrors its parsed crate::json::Json. Absent members and explicit
 * nulls both read as WNull, the same coalescing the wire readers apply.
 */
enum WireValue {
    WNull;
    WBool(value:Bool);
    WNum(value:Float);
    WStr(value:String);
    WArr(items:Array<WireValue>);
    WObj(fields:Array<WireField>);
}
