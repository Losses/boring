package boring;

import std.StringBuf;
import std.UStringException;
import std.UStringFault;

/**
 * Buffered string construction through std.StringBuf
 * (docs/specs/stdlib/08-string-buffer.md), including the
 * unpaired-surrogate fault paths: the buffer operations throw, so every
 * fallible shape here either returns through its own fault or catches
 * the fault into a classified value.
 */
class StringBufOps {
    public static function buildEmpty():String {
        final buf = new StringBuf();
        return buf.toString();
    }

    public static function buildParts(a:String, b:String, c:String):String {
        final buf = new StringBuf();
        buf.add(a);
        buf.add(b);
        buf.add(c);
        return buf.toString();
    }

    public static function buildWithChars(prefix:String, codeA:Int, codeB:Int):String {
        final buf = new StringBuf();
        buf.add(prefix);
        buf.addChar(codeA);
        buf.addChar(codeB);
        return buf.toString();
    }

    public static function measureLength(parts:Array<String>):Int {
        final buf = new StringBuf();
        for (i in 0...parts.length) {
            buf.add(parts[i]);
        }
        return buf.length;
    }

    public static function buildIncremental():Array<String> {
        final buf = new StringBuf();
        buf.add("step1");
        final s1 = buf.toString();
        buf.add("-step2");
        final s2 = buf.toString();
        return [s1, s2];
    }

    public static function buildSupplementary():String {
        final buf = new StringBuf();
        buf.add("hi");
        buf.add("🚀");
        buf.add("!");
        return buf.toString();
    }

    public static function measureSupplementaryLength():Int {
        final buf = new StringBuf();
        buf.add("hi");
        buf.add("🚀");
        buf.add("!");
        return buf.length;
    }

    /** A lead completed by the immediately following addChar (stdlib/08). */
    public static function completePair(lead:Int, trail:Int):String {
        final buf = new StringBuf();
        buf.addChar(lead);
        buf.addChar(trail);
        return buf.toString();
    }

    /** Fault identity per variant: distinct class ranges, never messages. */
    static function classifyFault(fault:UStringFault):Int {
        return switch (fault) {
            case InvalidCodePoint(code): 1000 + code;
            case UnpairedSurrogate(unit): 2000 + unit;
        };
    }

    /** A trail without a preceding lead: the argument unit names the fault. */
    public static function caughtTrailUnit(trail:Int):Int {
        final value = try {
            final buf = new StringBuf();
            buf.addChar(trail);
            0;
        } catch (error:UStringException) {
            classifyFault(error.fault);
        };
        return value;
    }

    /** A dangling lead observed by toString: the held unit names the fault. */
    public static function caughtDanglingUnit(lead:Int):Int {
        final value = try {
            final buf = new StringBuf();
            buf.addChar(lead);
            final text = buf.toString();
            text.length;
        } catch (error:UStringException) {
            classifyFault(error.fault);
        };
        return value;
    }

    /** An add that strands a held lead: the held unit names the fault. */
    public static function caughtAddAfterLeadUnit(lead:Int):Int {
        final value = try {
            final buf = new StringBuf();
            buf.addChar(lead);
            buf.add("x");
            0;
        } catch (error:UStringException) {
            classifyFault(error.fault);
        };
        return value;
    }
}
