package ptr;

import std.Console;
import swift.Buffer;

/**
    Two deliberate lifetime mistakes for the block A record. `leak` allocates
    a buffer and returns without freeing it; `doubleFree` frees the same
    buffer twice. Each runs in its own process so the outcome of one cannot
    hide the other.
**/
class BufferLifetime {
    public static function main():Void {}

    public static function leak():Void {
        final buffer:Buffer<Int> = Buffer.alloc(8, 0);
        buffer.set(0, 1);
        Console.log("leak allocated");
    }

    public static function doubleFree():Void {
        final buffer:Buffer<Int> = Buffer.alloc(8, 0);
        buffer.free(8);
        Console.log("double free first");
        buffer.free(8);
        Console.log("double free second survived");
    }
}
