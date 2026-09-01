package boring;

import haxe.io.Bytes;

/** Fixed-length byte allocation and mutation capability. */
class BytesOps {
	public static function build():Bytes {
		final out = Bytes.alloc(8);
		out.set(0, 1);
		out.set(1, 2);
		final source = Bytes.alloc(4);
		source.set(0, 10);
		source.set(1, 11);
		source.set(2, 12);
		source.set(3, 13);
		out.blit(2, source, 1, 3);
		out.fill(5, 2, 0xA5);
		return out;
	}
}
