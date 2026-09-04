package boring;

import std.StringBuf;

/**
 * Raw payload table using compile-time expanded UTF-16 code units
 * (docs/specs/features/20-compile-time-data-tables.md). The data file is
 * synthetic, named as synthetic in the specification; string payloads ride
 * the integer data-table emission, and decoding with String.fromCharCode
 * at runtime reconstructs the file content exactly.
 */
@:build(DataTables.codeUnitsField("samples/data/synthetic-payload-text.txt", "TEXT_UNITS"))
class PayloadTextTable {
    public static function text():String {
        final output = new StringBuf();
        var index:Int = 0;
        while (index < TEXT_UNITS.length) {
            output.add(String.fromCharCode(TEXT_UNITS[index]));
            index += 1;
        }
        return output.toString();
    }

    public static function unitCount():Int {
        return TEXT_UNITS.length;
    }

    public static function unitAt(index:Int):Int {
        return TEXT_UNITS[index];
    }
}
