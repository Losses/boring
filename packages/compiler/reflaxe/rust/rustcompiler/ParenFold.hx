package rustcompiler;

#if (macro || reflaxe_runtime)
/**
    Folds doubled parentheses in generated Rust text: `((A))` becomes
    `(A)` whenever the inner text carries no top-level comma, so a tuple
    argument never turns into a second argument. String literals are
    skipped. The fold repeats until no doubled pair remains. (ParenFold)
**/
class ParenFold {
    public static function strip(text:String):String {
        var out = text;
        var changed = true;
        var guard = 0;
        while (changed && guard < 8) {
            changed = false;
            guard++;
            out = foldOnce(out, function() changed = true);
        }
        return out;
    }

    static function foldOnce(text:String, onChange:Void->Void):String {
        final out = new StringBuf();
        var i = 0;
        var inString = false;
        while (i < text.length) {
            final c = text.charAt(i);
            if (inString) {
                out.add(c);
                if (c == "\\") {
                    if (i + 1 < text.length) {
                        out.add(text.charAt(i + 1));
                        i++;
                    }
                } else if (c == "\"") {
                    inString = false;
                }
                i++;
                continue;
            }
            if (c == "\"") {
                inString = true;
                out.add(c);
                i++;
                continue;
            }
            if (c == "(") {
                final close = matchParen(text, i);
                if (close > i + 1 && i > 0) {
                    // Condition position (`if (` / `while (`): the parens
                    // come from value-position rendering and Rust reads the
                    // expression bare. A leading brace (a struct literal)
                    // must keep its parens. (ParenFold)
                    final prev = prevSignificant(text, i);
                    if ((prev == "if " || prev == "while ") && close < text.length) {
                        // A callable in parens invoked right after the
                        // close, `(f)(x)`, needs its parens. (ParenFold)
                        var k = close + 1;
                        while (k < text.length && text.charAt(k) == " ")
                            k++;
                        if (k < text.length && text.charAt(k) == "(") {
                            out.add(c);
                            i++;
                            continue;
                        }
                        final inner = text.substr(i + 1, close - i - 1);
                        if (!hasTopLevelComma(text, i + 1, close)
                            && !foldChangesGrouping(text, i, close)
                            && !StringTools.startsWith(StringTools.ltrim(inner), "{")
                            && (StringTools.startsWith(StringTools.ltrim(inner), "match ") || !hasTopLevelBrace(text, i + 1, close))) {
                            out.add(inner);
                            i = close + 1;
                            onChange();
                            continue;
                        }
                    }
                    // Argument position (`(` or `,` before the group): a
                    // brace-block value and a cast read bare in a comma
                    // list. (ParenFold)
                    if (prev == "(" || prev == ",") {
                        final inner = text.substr(i + 1, close - i - 1);
                        final ltrimInner = StringTools.ltrim(inner);
                        var k = close + 1;
                        while (k < text.length && text.charAt(k) == " ")
                            k++;
                        if (StringTools.startsWith(ltrimInner, "{")
                            && !hasTopLevelComma(text, i + 1, close)
                            && !foldChangesGrouping(text, i, close)) {
                            out.add(ltrimInner);
                            i = close + 1;
                            onChange();
                            continue;
                        }
                        if (!StringTools.startsWith(ltrimInner, "*")
                            && castSuffixAt(ltrimInner)
                            && !hasTopLevelComma(text, i + 1, close)
                            && !foldChangesGrouping(text, i, close)) {
                            out.add(ltrimInner);
                            i = close + 1;
                            onChange();
                            continue;
                        }
                    }
                    // Assignment right side, match arm body, and block tail
                    // read bare the same way. (ParenFold)
                    final isMatchArm = prev == "=>";
                    final positional = prev == "=" || prev == ";" || prev == "{" || isMatchArm;
                    if (positional) {
                        final inner = text.substr(i + 1, close - i - 1);
                        final ltrimInner = StringTools.ltrim(inner);
                        var k = close + 1;
                        while (k < text.length && text.charAt(k) == " ")
                            k++;
                        // An assignment right side or block tail with a
                        // brace-block value reads bare (a match arm keeps
                        // its brace rejection: the arm body braces are part
                        // of the match syntax). (ParenFold)
                        final braceBlockOk = (prev == "=" || prev == ";" || prev == "{")
                            && !hasTopLevelComma(text, i + 1, close);
                        if (!(k < text.length && text.charAt(k) == "(")
                            && !(k < text.length && text.charAt(k) == ".")
                            && (!StringTools.startsWith(ltrimInner, "{") || braceBlockOk)
                            && !hasTopLevelComma(text, i + 1, close)
                            && !foldChangesGrouping(text, i, close)) {
                            out.add(inner);
                            i = close + 1;
                            onChange();
                            continue;
                        }
                    }
                    if (prev == "(" || prev == ",") {
                        final inner = text.substr(i + 1, close - i - 1);
                        final ltrim = StringTools.ltrim(inner);
                        if (StringTools.startsWith(ltrim, "(") && closeIndexAt(ltrim, 0) == ltrim.length - 1) {
                            // A fully wrapped inner expression: the outer
                            // pair is the doubled case handled below.
                        } else if (castSuffixAt(ltrim) && !hasTopLevelComma(text, i + 1, close) && !foldChangesGrouping(text, i, close)) {
                            out.add(inner);
                            i = close + 1;
                            onChange();
                            continue;
                        }
                    }
                }
            }
            if (c == "(" && i + 1 < text.length && text.charAt(i + 1) == "(") {
                final innerOpen = i + 1;
                final innerClose = matchParen(text, innerOpen);
                if (innerClose >= 0) {
                    final outerClose = matchParen(text, i);
                    if (outerClose == innerClose + 1 && innerClose > innerOpen + 1
                        && !hasTopLevelComma(text, innerOpen + 1, innerClose)
                        && !foldChangesGrouping(text, innerOpen, innerClose)) {
                        // Drop the inner pair: copy text[i] (the outer
                        // open), the inner content, then text[outerClose].
                        out.add(text.charAt(i));
                        out.add(text.substr(innerOpen + 1, innerClose - innerOpen - 1));
                        out.add(text.charAt(outerClose));
                        i = outerClose + 1;
                        onChange();
                        continue;
                    }
                }
            }
            out.add(c);
            i++;
        }
        return out.toString();
    }

    /**
        A fold may not change grouping. When the removed pair sits next to
        an operator, the tightest top-level operator inside must bind
        strictly tighter than that neighbor: Rust reads `a | b << c` as
        `a | (b << c)`, so `(a | b) << c` keeps its parens. A cast, a
        method call, an index, an invocation, and a unary prefix all bind
        at the top level (10), above every binary operator.
        (OperatorPrecedenceGuard)
    **/
    static function foldChangesGrouping(text:String, open:Int, close:Int):Bool {
        final innerTightest = tightestTopLevelPrecedence(text.substr(open + 1, close - open - 1));
        if (innerTightest <= 0)
            return false;
        var j = close + 1;
        while (j < text.length && isSpaceChar(text.charAt(j)))
            j++;
        if (j < text.length) {
            final succ = successorPrecedence(text, j);
            if (succ > 0 && innerTightest <= succ)
                return true;
        }
        var k = open - 1;
        while (k >= 0 && isSpaceChar(text.charAt(k)))
            k--;
        if (k >= 0) {
            final pred = predecessorPrecedence(text, k);
            if (pred > 0 && innerTightest <= pred)
                return true;
        }
        return false;
    }

    static function isSpaceChar(c:String):Bool {
        return c == " " || c == "\n" || c == "\r" || c == "\t";
    }

    static final BINARY_PRECEDENCE:Map<String, Int> = [
        "||" => 1,
        "&&" => 2,
        "==" => 3,
        "!=" => 3,
        "<=" => 3,
        ">=" => 3,
        "<<" => 7,
        ">>" => 7,
        "|" => 4,
        "^" => 5,
        "&" => 6,
        "+" => 8,
        "-" => 8,
        "*" => 9,
        "/" => 9,
        "%" => 9,
        "<" => 3,
        ">" => 3,
    ];

    /** Precedence of the operator token starting at `at`, or 0. A cast
        (` as `), a method call, an index, and an invocation bind at the
        top level. (OperatorPrecedenceGuard) */
    static function successorPrecedence(text:String, at:Int):Int {
        final two = text.substr(at, 2);
        if (BINARY_PRECEDENCE.exists(two))
            return BINARY_PRECEDENCE.get(two);
        final c = text.charAt(at);
        if (c == "." || c == "(" || c == "[")
            return 10;
        if (text.substr(at, 2) == "as") {
            final after = text.charAt(at + 2);
            if (after == " " || after == "\n" || after == "\r" || after == "\t" || after == ")" || after == ",")
                return 10;
        }
        return BINARY_PRECEDENCE.exists(c) ? BINARY_PRECEDENCE.get(c) : 0;
    }

    /** Precedence of the operator token ending at `at`, or 0. A prefix
        sign with no operand before it is unary and binds at the top
        level. (OperatorPrecedenceGuard) */
    static function predecessorPrecedence(text:String, at:Int):Int {
        if (at >= 1 && text.charAt(at) == ">" && text.charAt(at - 1) == "=") {
            // `=>` ends a match arm; the `>` is not a comparison.
            return 0;
        }
        final two = at >= 1 ? text.substr(at - 1, 2) : "";
        if (BINARY_PRECEDENCE.exists(two))
            return BINARY_PRECEDENCE.get(two);
        final c = text.charAt(at);
        if (!BINARY_PRECEDENCE.exists(c))
            return 0;
        if (unaryContextBefore(text, at))
            return 10;
        return BINARY_PRECEDENCE.get(c);
    }

    /** Whether the sign ending at `at` is a prefix operator: no operand
        (identifier, literal, closing bracket) sits before it.
        (OperatorPrecedenceGuard) */
    static function unaryContextBefore(text:String, at:Int):Bool {
        var k = at - 1;
        while (k >= 0 && isSpaceChar(text.charAt(k)))
            k--;
        if (k < 0)
            return true;
        final c = text.charAt(k);
        final isOperand = c == ")" || c == "]" || c == "}" || c == "_" || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9");
        return !isOperand;
    }

    /** Highest precedence among top-level operators in `text`. A cast
        target follows the last top-level ` as `; its angle brackets are
        type syntax, not comparisons. (OperatorPrecedenceGuard) */
    static function tightestTopLevelPrecedence(text:String):Int {
        var depth = 0;
        var inString = false;
        var tightest = 0;
        var i = 0;
        while (i < text.length) {
            final c = text.charAt(i);
            if (inString) {
                if (c == "\\") {
                    i++;
                } else if (c == "\"") {
                    inString = false;
                }
                i++;
                continue;
            }
            if (c == "\"") {
                inString = true;
                i++;
                continue;
            }
            if (c == "(" || c == "[" || c == "{") {
                depth++;
            } else if (c == ")" || c == "]" || c == "}") {
                depth--;
            } else if (depth == 0) {
                if (c == " " && text.substr(i, 4) == " as ") {
                    break;
                }
                final two = text.substr(i, 2);
                if (BINARY_PRECEDENCE.exists(two) && two.length == 2) {
                    if (BINARY_PRECEDENCE.get(two) > tightest)
                        tightest = BINARY_PRECEDENCE.get(two);
                    i += 2;
                    continue;
                }
                if (BINARY_PRECEDENCE.exists(c)) {
                    if (unaryContextBefore(text, i))
                        tightest = 10
                    else if (BINARY_PRECEDENCE.get(c) > tightest)
                        tightest = BINARY_PRECEDENCE.get(c);
                }
            }
            i++;
        }
        return tightest;
    }

    static function matchParen(text:String, open:Int):Int {


        var depth = 0;
        var inString = false;
        var i = open;
        while (i < text.length) {
            final c = text.charAt(i);
            if (inString) {
                if (c == "\\") i++;
                else if (c == "\"") inString = false;
            } else if (c == "\"") {
                inString = true;
            } else if (c == "(") {
                depth++;
            } else if (c == ")") {
                depth--;
                if (depth == 0)
                    return i;
            }
            i++;
        }
        return -1;
    }

    static function hasTopLevelComma(text:String, from:Int, to:Int):Bool {
        var depth = 0;
        var inString = false;
        var i = from;
        while (i < to) {
            final c = text.charAt(i);
            if (inString) {
                if (c == "\\") i++;
                else if (c == "\"") inString = false;
            } else if (c == "\"") {
                inString = true;
            } else if (c == "(" || c == "[" || c == "{") {
                depth++;
            } else if (c == ")" || c == "]" || c == "}") {
                depth--;
            } else if (c == "," && depth == 0) {
                return true;
            }
            i++;
        }
        return false;
    }

    static function prevSignificant(text:String, at:Int):String {
        var j = at - 1;
        while (j >= 0 && (text.charAt(j) == " " || text.charAt(j) == "\n" || text.charAt(j) == "\r" || text.charAt(j) == "\t"))
            j--;
        if (j < 0)
            return "";
        // The keyword form needs the characters before the token too.
        if (j >= 1 && text.charAt(j) == ">" && j >= 1 && text.substr(j - 1, 2) == "=>")
            return "=>";
        if (j >= 1 && text.substr(j - 1, 3) == "if ")
            return "if ";
        if (j >= 5 && text.substr(j - 5, 6) == "while ")
            return "while ";
        return text.charAt(j);
    }

    static function hasTopLevelBrace(text:String, from:Int, to:Int):Bool {
        var depth = 0;
        var inString = false;
        var i = from;
        while (i < to) {
            final c = text.charAt(i);
            if (inString) {
                if (c == "\\") i++;
                else if (c == "\"") inString = false;
            } else if (c == "\"") {
                inString = true;
            } else if (c == "(" || c == "[" || c == "{") {
                depth++;
            } else if (c == ")" || c == "]" || c == "}") {
                depth--;
            } else if (c == "{" && depth == 0) {
                return true;
            }
            i++;
        }
        return false;
    }

    static function castSuffixAt(text:String):Bool {
        // `X as T` at top level: the last top-level ` as ` sits outside any
        // grouping and the text carries no top-level comma.
        var depth = 0;
        var inString = false;
        var i = 0;
        var asAt = -1;
        while (i < text.length - 3) {
            final c = text.charAt(i);
            if (inString) {
                if (c == "\\") i++;
                else if (c == "\"") inString = false;
            } else if (c == "\"") {
                inString = true;
            } else if (c == "(" || c == "[" || c == "{") {
                depth++;
            } else if (c == ")" || c == "]" || c == "}") {
                depth--;
            } else if (c == " " && depth == 0 && text.substr(i, 4) == " as ") {
                asAt = i;
            }
            i++;
        }
        if (asAt < 0)
            return false;
        final tail = StringTools.trim(text.substr(asAt + 4));
        for (bad in [" ", ",", "+", "-", "*", "/", "&&", "||"])
            if (tail.indexOf(bad) >= 0)
                return false;
        return true;
    }

    static function closeIndexAt(text:String, open:Int):Int {
        var depth = 0;
        var inString = false;
        var i = open;
        while (i < text.length) {
            final c = text.charAt(i);
            if (inString) {
                if (c == "\\") i++;
                else if (c == "\"") inString = false;
            } else if (c == "\"") {
                inString = true;
            } else if (c == "(") {
                depth++;
            } else if (c == ")") {
                depth--;
                if (depth == 0)
                    return i;
            }
            i++;
        }
        return -1;
    }
}
#end
