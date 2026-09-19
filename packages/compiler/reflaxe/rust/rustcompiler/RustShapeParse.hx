package rustcompiler;

/**
 * Exact Option-shape parser over rendered Rust text. See RustShape.hx for
 * the shape values. (ShapeParse)
 */
class RustShapeParse {
    /** Method suffixes that preserve Option-ness of their receiver. */
    static final preservingSuffixes:Array<String> = [
        ".clone()", ".to_string()", ".to_owned()", ".as_str()", ".as_ref()",
        ".to_vec()", ".to_uppercase()", ".to_lowercase()",
    ];

    /** Rendered-text shapes cached per source text. Identical texts have
        identical shapes, and slot boundaries re-read the same argument
        texts, so the cache stays small. */
    static final cache:Map<String, RustShape> = [];

    public static function shapeOf(text:String):RustShape {
        final trimmed = StringTools.trim(text);
        if (trimmed == "")
            return ShapeUnknown;
        final cached = cache.get(trimmed);
        if (cached != null)
            return cached;
        final result = parse(trimmed);
        cache.set(trimmed, result);
        return result;
    }

    static function parsePeelOnly(text:String):RustShape {
        var s = StringTools.trim(text);
        var changed = true;
        while (changed) {
            changed = false;
            if (StringTools.startsWith(s, "&")) {
                s = StringTools.trim(s.substr(1));
                if (StringTools.startsWith(s, "mut ")) {
                    s = StringTools.trim(s.substr(4));
                }
                changed = true;
                continue;
            }
            if (StringTools.startsWith(s, "(") && closeIndexOf(s, "(", ")") == s.length - 1) {
                s = StringTools.trim(s.substr(1, s.length - 2));
                changed = true;
                continue;
            }
            if (StringTools.startsWith(s, "{") && closeIndexOf(s, "{", "}") == s.length - 1) {
                s = StringTools.trim(s.substr(1, s.length - 2));
                changed = true;
                continue;
            }
            for (suffix in preservingSuffixes) {
                if (StringTools.endsWith(s, suffix)) {
                    s = StringTools.trim(s.substr(0, s.length - suffix.length));
                    changed = true;
                    break;
                }
            }
            if (changed)
                continue;
            if (StringTools.endsWith(s, "?")) {
                s = StringTools.trim(s.substr(0, s.length - 1));
                if (StringTools.startsWith(s, "(") && closeIndexOf(s, "(", ")") == s.length - 1) {
                    s = StringTools.trim(s.substr(1, s.length - 2));
                }
                return parse(s) == ShapeOption ? ShapeBare : parse(s);
            }
        }
        return RustShape.ShapeUnknown;
    }

    static function parse(text:String):RustShape {
        var s = StringTools.trim(text);
        // Peel forms that do not change the answer.
        var changed = true;
        while (changed) {
            changed = false;
            if (StringTools.startsWith(s, "&")) {
                s = StringTools.trim(s.substr(1));
                if (StringTools.startsWith(s, "mut ")) {
                    s = StringTools.trim(s.substr(4));
                }
                changed = true;
                continue;
            }
            if (StringTools.startsWith(s, "(") && closeIndexOf(s, "(", ")") == s.length - 1) {
                s = StringTools.trim(s.substr(1, s.length - 2));
                changed = true;
                continue;
            }
            if (StringTools.startsWith(s, "{") && closeIndexOf(s, "{", "}") == s.length - 1) {
                s = StringTools.trim(s.substr(1, s.length - 2));
                changed = true;
                continue;
            }
            // One shape-preserving method call at the tail.
            for (suffix in preservingSuffixes) {
                if (StringTools.endsWith(s, suffix)) {
                    s = StringTools.trim(s.substr(0, s.length - suffix.length));
                    changed = true;
                    break;
                }
            }
            if (changed)
                continue;
            // The try operator consumes the Option (or Result) wrapper.
            if (StringTools.endsWith(s, "?")) {
                s = StringTools.trim(s.substr(0, s.length - 1));
                // `(...)`? leaves the inner bare value.
                if (StringTools.startsWith(s, "(") && closeIndexOf(s, "(", ")") == s.length - 1) {
                    s = StringTools.trim(s.substr(1, s.length - 2));
                }
                return parse(s) == ShapeOption ? ShapeBare : parse(s);
            }
        }
        // Option constructors.
        if (s == "None" || StringTools.startsWith(s, "None\n") || s == "None;")
            return ShapeOption;
        if (StringTools.startsWith(s, "Some(") && closeIndexOf(s, "(", ")") == s.length - 1)
            return ShapeOption;
        if (StringTools.startsWith(s, "Option::<") || StringTools.startsWith(s, "Option<"))
            return ShapeOption;
        // Forcing reads consume the wrapper.
        for (consumer in [".unwrap()", ".unwrap_or_default()"]) {
            if (StringTools.endsWith(s, consumer))
                return ShapeBare;
        }
        if (endsWithCall(s, ".unwrap_or(") || endsWithCall(s, ".unwrap_or_else(")
            || endsWithCall(s, ".unwrap_or_default("))
            return ShapeBare;
        // A cast or deref of an Option stays an Option only in text forms
        // the generator does not produce; treat plain casts of unknown
        // receivers as unknown.
        // Composites: the answer is the agreement of their arms.
        if (StringTools.startsWith(s, "if ")) {
            final arms = ifArmBodies(s);
            if (arms != null)
                return armShape(arms);
            return ShapeUnknown;
        }
        if (StringTools.startsWith(s, "match")) {
            final arms = matchArmBodies(s);
            if (arms != null)
                return armShape(arms);
            return ShapeUnknown;
        }
        // Ternary-shaped helper forms the generator emits for coalescing
        // (`{ A }.unwrap_or(B)` was handled above by the tail rule).
        return ShapeUnknown;
    }

    /** Shape agreement across composite arms. */
    static function armShape(arms:Array<String>):RustShape {
        var sawOption = false;
        var sawBare = false;
        for (arm in arms) {
            final aShape = parse(StringTools.trim(arm));
            switch (aShape) {
                case ShapeOption:
                    sawOption = true;
                case ShapeBare:
                    sawBare = true;
                case _:
                    return ShapeUnknown;
            }
        }
        if (sawOption && sawBare)
            return ShapeMixed;
        return sawOption ? ShapeOption : ShapeBare;
    }

    /** Arm bodies of a rendered `if cond { A } else { B }` expression.
        Chains of `else if` flatten into one arm list. */
    static function ifArmBodies(s:String):Null<Array<String>> {
        final open = s.indexOf("{");
        if (open < 0)
            return null;
        final close = closeIndexOf(s, "{", "}");
        if (close < 0)
            return null;
        final then = s.substr(open + 1, close - open - 1);
        final rest = StringTools.trim(s.substr(close + 1));
        final arms = [then];
        if (rest == "")
            return arms;
        if (StringTools.startsWith(rest, "else")) {
            final tail = StringTools.trim(rest.substr(4));
            if (StringTools.startsWith(tail, "if ")) {
                final nested = ifArmBodies(tail);
                if (nested == null)
                    return null;
                for (a in nested)
                    arms.push(a);
                return arms;
            }
            if (StringTools.startsWith(tail, "{") && closeIndexOf(tail, "{", "}") == tail.length - 1) {
                arms.push(tail.substr(1, tail.length - 2));
                return arms;
            }
        }
        // A trailing fragment that is not an else (a statement boundary the
        // caller handed us) leaves the shape undecidable here.
        return null;
    }

    /** Arm bodies of a rendered `match subject { pat => body, ... }`. */
    static function matchArmBodies(s:String):Null<Array<String>> {
        final open = s.indexOf("{");
        if (open < 0)
            return null;
        final close = closeIndexOf(s, "{", "}");
        if (close < 0 || close != s.length - 1)
            return null;
        final body = s.substr(open + 1, close - open - 1);
        final arms:Array<String> = [];
        var depth = 0;
        var start = 0;
        var inStr = false;
        var i = 0;
        while (i < body.length) {
            final ch = body.charAt(i);
            if (inStr) {
                if (ch == "\\") {
                    i += 2;
                    continue;
                }
                if (ch == "\"")
                    inStr = false;
                i++;
                continue;
            }
            switch (ch) {
                case "\"":
                    inStr = true;
                case "{", "(", "[":
                    depth++;
                case "}", ")", "]":
                    depth--;
                case ",":
                    if (depth == 0) {
                        arms.push(body.substr(start, i - start));
                        start = i + 1;
                    }
                case _:
            }
            i++;
        }
        arms.push(body.substr(start));
        final bodies:Array<String> = [];
        for (arm in arms) {
            final a = StringTools.trim(arm);
            if (a == "")
                continue;
            final arrow = armBodyStart(a);
            if (arrow < 0)
                return null;
            bodies.push(a.substr(arrow + 2));
        }
        return bodies;
    }

    /** Index of the `=>` that separates a match arm's pattern from its
        body, at brace depth zero. */
    static function armBodyStart(arm:String):Int {
        var depth = 0;
        var i = 0;
        while (i < arm.length - 1) {
            final ch = arm.charAt(i);
            switch (ch) {
                case "{", "(", "[":
                    depth++;
                case "}", ")", "]":
                    depth--;
                case "=":
                    if (depth == 0 && arm.charAt(i + 1) == ">" && (i == 0 || arm.charAt(i - 1) != "="))
                        return i;
                case "-":
                    if (depth == 0 && arm.charAt(i + 1) == ">")
                        return -1;
                case _:
            }
            i++;
        }
        return -1;
    }

    /** True when `text` ends with a balanced call of the given method
        name: the tail from the method token to the final character is one
        complete parenthesized argument list. */
    static function endsWithCall(text:String, method:String):Bool {
        if (!StringTools.endsWith(text, ")"))
            return false;
        // Scan occurrences right to left; the call that closes exactly at
        // the final character wins (an inner call of the same name must
        // not shadow the outer tail call).
        var from = text.length;
        while (from >= method.length) {
            final open = text.lastIndexOf(method, from - method.length);
            if (open < 0)
                return false;
            final head = text.substr(open + method.length);
            if (StringTools.startsWith(head, "(") && closeIndexOf(head, "(", ")") == head.length - 1)
                return true;
            if (open == 0)
                return false;
            from = open;
        }
        return false;
    }

    /** Index of the parenthesis/brace that closes the opener at index 0,
        or -1. String literals are skipped. */
    public static function closeIndexOf(text:String, open:String, close:String):Int {
        var depth = 0;
        var inStr = false;
        var i = 0;
        while (i < text.length) {
            final ch = text.charAt(i);
            if (inStr) {
                if (ch == "\\") {
                    i += 2;
                    continue;
                }
                if (ch == "\"")
                    inStr = false;
                i++;
                continue;
            }
            if (ch == "\"") {
                inStr = true;
            } else if (ch == open) {
                depth++;
            } else if (ch == close) {
                depth--;
                if (depth == 0)
                    return i;
            }
            i++;
        }
        return -1;
    }
}
