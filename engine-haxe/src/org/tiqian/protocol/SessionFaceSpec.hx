package org.tiqian.protocol;

/**
 * A face spec paired with the source order the session layer resolved for
 * it, as orderedFaceSpecs emits before selection (protocol 5.3).
 * sourceOrder is null until the session layer assigns it.
 */
typedef SessionFaceSpec = {
    final spec:FontFaceSpec;
    final sourceOrder:Null<Float>;
}
