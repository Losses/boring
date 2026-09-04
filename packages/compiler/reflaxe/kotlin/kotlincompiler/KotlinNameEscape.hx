package kotlincompiler;

/**
    Identifier escaping: Kotlin hard keywords used as Haxe names render in
    backticks at every emission site that prints an identifier.
**/
class KotlinNameEscape {
    static final keywords:Map<String, Bool> = [
        for (k in [
            "as",
            "break",
            "class",
            "continue",
            "do",
            "else",
            "false",
            "for",
            "fun",
            "if",
            "in",
            "interface",
            "is",
            "null",
            "object",
            "package",
            "return",
            "super",
            "this",
            "throw",
            "true",
            "try",
            "typealias",
            "typeof",
            "val",
            "var",
            "when",
            "while"
        ])
            k => true
    ];

    public static function escape(name:String):String {
        return keywords.exists(name) ? "`" + name + "`" : name;
    }
}
