package boring;

import haxe.io.Bytes;

/**
 * Minimal regression for the Rust target's printed form: a payload enum whose
 * payload is haxe.io.Bytes must compile its labeled printed form (the payload
 * has no Display, so the print leans on Debug like the growth variants).
 */
enum BytesFrame {
    Frame(data:Bytes);
}
