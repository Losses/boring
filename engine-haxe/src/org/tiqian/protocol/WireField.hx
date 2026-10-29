package org.tiqian.protocol;

/**
 * One entry of a WObj. The list order inside WObj is the identity order: the
 * canonical encoder carries attribute pairs in exactly this order, so every
 * adapter that builds a WObj from a platform map must keep insertion order
 * (JavaScript's own property order, the Rust Json parser's document order).
 */
typedef WireField = {
    final name:String;
    final value:WireValue;
}
