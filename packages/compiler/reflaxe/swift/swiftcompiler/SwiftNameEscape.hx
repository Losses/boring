package swiftcompiler;

/**
    Identifier escaping: Swift reserved words used as Haxe names render in
    backticks at every emission site that prints an identifier.
**/
class SwiftNameEscape {
    static final keywords:Map<String, Bool> = [
        for (k in [
            "associatedtype",
            "class",
            "deinit",
            "enum",
            "extension",
            "fileprivate",
            "func",
            "import",
            "init",
            "inout",
            "internal",
            "let",
            "open",
            "operator",
            "private",
            "precedencegroup",
            "protocol",
            "public",
            "rethrows",
            "static",
            "struct",
            "subscript",
            "typealias",
            "var",
            "break",
            "case",
            "continue",
            "default",
            "defer",
            "do",
            "else",
            "fallthrough",
            "for",
            "guard",
            "if",
            "in",
            "repeat",
            "return",
            "switch",
            "where",
            "while",
            "as",
            "Any",
            "catch",
            "false",
            "is",
            "nil",
            "self",
            "Self",
            "super",
            "throw",
            "throws",
            "true",
            "try",
        ])
            k => true
    ];

    public static function escape(name:String):String {
        return keywords.exists(name) ? "`" + name + "`" : name;
    }
}
