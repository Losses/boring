package boring;

class NumericDomainOps {
    // Pattern 1: `> 0` positive check on a business index (number_symbol_cohesion).
    public static function prefixUnit(text:String, start:Int):Int {
        if (start > 0) {
            return text.charCodeAt(start - 1);
        }
        return 0;
    }

    // Pattern 2: `m < word.length - 1` loop (liang_hyphenator).
    public static function offsets(word:String):Array<Int> {
        final result:Array<Int> = [];
        var m = 0;
        while (m < word.length - 1) {
            final offset = m + 1;
            if (offset >= 1 && offset <= word.length - 1) {
                result.push(offset);
            }
            m++;
        }
        return result;
    }

    // Pattern 3: `found < 0` sentinel + assignment from u32 loop var (width_independent).
    public static function findIndex(values:Array<Int>, key:Int):Int {
        var found:Int = -1;
        var i = 0;
        while (i < values.length) {
            if (values[i] == key) {
                found = i;
                break;
            }
            i++;
        }
        if (found < 0) {
            return 0;
        }
        return values[found];
    }

    // Pattern 5: charCodeAt with i32-domain index (contextual_dash_ellipsis).
    public static function beforeChar(text:String, end:Int):Int {
        final lastIndex = end - 1;
        if (lastIndex > 0) {
            return text.charCodeAt(lastIndex - 1);
        }
        return text.charCodeAt(lastIndex);
    }

    // Pattern 6: vec literal with i32-domain element (paragraph_shaping).
    public static function colonPair(token:String, close:Int):Array<Int> {
        final colon = token.indexOf(":", close + 1);
        if (colon != close + 1) {
            return [];
        }
        return [close, colon + 1];
    }

    // Pattern 7: push of i32-domain value into u32 array (liang_hyphenator).
    public static function collectOffsets(word:String):Array<Int> {
        final result:Array<Int> = [];
        var m = 0;
        while (m < word.length - 1) {
            final offset = m + 1;
            result.push(offset);
            m++;
        }
        return result;
    }
}