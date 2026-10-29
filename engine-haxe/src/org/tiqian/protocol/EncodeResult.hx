package org.tiqian.protocol;

import haxe.io.Bytes;

/** The encode outcome: bytes or the named issue the platform adapter raises. */
enum EncodeResult {
    COk(bytes:Bytes);
    CErr(issue:String);
}