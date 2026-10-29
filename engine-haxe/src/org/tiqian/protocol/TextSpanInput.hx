package org.tiqian.protocol;

/**
 * One styled run. The ranges live in UTF-16 code units, the engine's
 * TextRange space (stdlib/06-std-modules.md:318 String.length is UTF-16
 * unit access).
 */
typedef TextSpanInput = {
    var start:Int;
    var end:Int;
    var families:Array<String>;
    var fontSizePx:Float;
    var fontWeight:Int;
    var italic:Bool;
    var baselineShift:Float;
}
