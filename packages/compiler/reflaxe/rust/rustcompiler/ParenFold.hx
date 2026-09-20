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
                            && !StringTools.startsWith(StringTools.ltrim(inner), "{")
                            && (StringTools.startsWith(StringTools.ltrim(inner), "match ") || !hasTopLevelBrace(text, i + 1, close))) {
                            out.add(inner);
                            i = close + 1;
                            onChange();
                            continue;
                        }
                    }
                    // Argument position: a cast needs no surrounding parens
                    // in a comma list. (ParenFold)
                    // Assignment right side, match arm body, and block
                    // tail read bare the same way. (ParenFold)
                    final isMatchArm = prev == "=>";
                    final positional = prev == "=" || prev == ";" || isMatchArm;
                    if (positional) {
                        var k = close + 1;
                        while (k < text.length && text.charAt(k) == " ")
                            k++;
                        final inner = text.substr(i + 1, close - i - 1);
                        final ltrimInner = StringTools.ltrim(inner);
                        // The `.` and `(` successor checks already guard
                        // the deref and callable bindings; a leading `*` in
                        // a comparison arm is safe to unwrap.
                        // (ParenFold)
                        if (!(k < text.length && text.charAt(k) == "(")
                            && !(k < text.length && text.charAt(k) == ".")
                            && !hasTopLevelComma(text, i + 1, close)
                            && !StringTools.startsWith(ltrimInner, "{")) {
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
                        } else if (castSuffixAt(ltrim) && !hasTopLevelComma(text, i + 1, close)) {
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
                        && !hasTopLevelComma(text, innerOpen + 1, innerClose)) {
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
        while (j >= 0 && text.charAt(j) == " ")
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
