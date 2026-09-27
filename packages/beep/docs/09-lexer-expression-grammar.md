# Lexer and expression grammar

## 1. Token model

The scanner consumes UTF-8 bytes and emits tokens with kind, byte start, byte end, decoded payload, and line/column start. The end offset is exclusive. Invalid UTF-8 emits one diagnostic and a recovery token covering the invalid sequence. The parser never receives an invalid scalar.

Token kinds are identifier, integer, float, string, interpolation start, interpolation end, operator, delimiter, keyword, newline, and end. Whitespace other than newline is discarded. A backslash followed by a newline continues the current token line and emits no newline token.

The scanner uses maximal munch. An identifier keyword is classified as a keyword after decoding. A minus before digits remains an operator followed by an integer. A dot followed by a digit starts a float only when the preceding token cannot end an expression.

## 2. Lexical productions

    letter       = UnicodeLetter | "_" ;
    digit        = "0" ... "9" ;
    hex          = digit | "a" ... "f" | "A" ... "F" ;
    identifier   = letter { letter | digit } ;
    decimal      = digit { digit | "_" } ;
    binary       = "0b" { "0" | "1" | "_" } ;
    octal        = "0o" { "0" ... "7" | "_" } ;
    hexadecimal  = "0x" { hex | "_" } ;
    exponent     = ("e" | "E") ["+" | "-"] decimal ;
    float        = decimal "." decimal [exponent] | decimal exponent ;
    escape       = "\\" ("\\" | "\"" | "n" | "r" | "t" | "0" | "u{" hex {hex} "}") ;
    string       = "\"" { scalar | escape | interpolation } "\"" ;
    interpolation = "%(" expression ")" ;
    blockString  = "\"\"\"" { scalar | newline } "\"\"\"" ;

Numeric underscores occur between digits in their base. A float has at most one decimal point and one exponent. Integer overflow is reported while decoding the literal.

## 3. Operators and delimiters

Delimiters are (, ), [, ], {, }, ,, :, ;, ., and ?. Operators are +, -, *, /, %, **, <<, >>, &, ^, |, ~, !, ==, !=, <, <=, >, >=, &&, ||, .., ..=, =, +=, -=, *=, /=, %=, =>, and ->. The scanner reports an unknown operator character at its byte range.

The token sequence ? is postfix propagation only when the parser has a preceding Result expression. A standalone question mark is a syntax error. ?. is not an optional-member operator because null does not exist.

## 4. Complete expression grammar

    expression       = assignment ;
    assignment       = conditional [assignOp assignment] ;
    conditional      = logicalOr ["?" expression ":" conditional] ;
    logicalOr        = logicalAnd { "||" logicalAnd } ;
    logicalAnd      = bitOr { "&&" bitOr } ;
    bitOr            = bitXor { "|" bitXor } ;
    bitXor           = bitAnd { "^" bitAnd } ;
    bitAnd           = equality { "&" equality } ;
    equality         = relation { ("==" | "!=") relation } ;
    relation         = shift { ("<" | "<=" | ">" | ">=" | "is") shift } ;
    shift            = range { ("<<" | ">>") range } ;
    range            = additive [ (".." | "..=") additive ] ;
    additive         = multiplicative { ("+" | "-") multiplicative } ;
    multiplicative   = prefix { ("*" | "/" | "%" | "**") prefix } ;
    prefix           = ("!" | "-" | "~") prefix | postfix ;
    postfix          = primary { call | member | subscript | propagate } ;
    call             = arguments [blockArgument] ;
    member           = "." identifier [arguments] ;
    subscript        = "[" [expressions] "]" ;
    propagate        = "?" ;
    primary          = literal | identifier | "this" | "super" member
                     | "(" [expressions] ")" | array | map | functionLiteral
                     | match | if ;
    arguments        = "(" [argument {"," argument}] ")" ;
    argument         = [label ":"] expression ;
    blockArgument    = "{" block "}" ;
    array            = "[" [expressions] "]" ;
    map              = "{" [mapEntry {"," mapEntry}] "}" ;
    mapEntry         = expression ":" expression ;
    functionLiteral  = "fn" [typeParams] parameters [":" type] block ;
    expressions      = expression {"," expression} ;
    assignOp         = "=" | "+=" | "-=" | "*=" | "/=" | "%=" ;

Calls, member access, subscripts, and postfix propagation bind from left to right. Parenthesized one-expression groups preserve the expression type. Parenthesized comma expressions create tuples.

## 5. Declarations and patterns

Visibility is public or private, with private as the default inside a module. A name is an identifier. A qualified name is name {"." name}. A where clause is where constraint {"," constraint}; a constraint is type ":" interfaceType or projection "==" type. Foreign declarations use foreign before class, field, or method and contain signatures without Beep bodies.

    pattern = "_" | binding | literalPattern | tuplePattern | recordPattern
            | enumPattern | optionPattern | resultPattern | classPattern ;
    binding = identifier ;
    literalPattern = bool | integer | string ;
    tuplePattern = "(" [pattern {"," pattern}] ")" ;
    recordPattern = "{" fieldPattern {"," fieldPattern} "}" ;
    fieldPattern = identifier [":" pattern] ;
    enumPattern = qualifiedName ["(" [pattern {"," pattern}] ")"] ;
    optionPattern = "None" | "Some" "(" pattern ")" ;
    resultPattern = "Ok" "(" pattern ")" | "Err" "(" pattern ")" ;
    classPattern = qualifiedName "(" [pattern {"," pattern}] ")" ;

Pattern bindings are immutable. Duplicate bindings in one pattern are errors. A record pattern names fields by key. A class pattern is legal only for a declared class or interface relation.

## 6. Parser recovery and source maps

On an error, the parser consumes tokens until a delimiter at the current recovery depth, a statement newline, or a declaration keyword. It emits one recovery node with the original span. Recovery nodes cannot reach type checking or bytecode generation. Every AST node stores start/end offsets and module id. Bytecode source maps map instruction ranges to the smallest enclosing AST span.

## 7. Lexer tests

Test every token production, comment nesting, CR/LF variants, invalid UTF-8, maximal munch boundaries, numeric bases, overflow, escapes, interpolation nesting, operator pairs, delimiter recovery, and source-map offsets. Property tests scan then format tokens and assert stable token kinds and payloads.
