package boring;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * Minimal regression for the Rust target's field-initializer lowering: a
 * field-initialized BytesBuffer must construct through the runtime
 * BytesBuffer::new (a Default-dependent literal would fail to compile before
 * the runtime gained Default, and must still wire the real buffer).
 */
class BufferHolder {
    final buf:BytesBuffer = new BytesBuffer();

    public function new() {}

    public function writeByte(value:Int):Void {
        buf.addByte(value & 0xFF);
    }

    public function finish():Bytes {
        return buf.getBytes();
    }
}
