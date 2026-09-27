# Language overview and grammar

## 1. Scope and conformance

Beep source semantics are target-independent. The compiler resolves every reachable module, parses it, performs complete static checking, generates bytecode, and verifies bytecode before user code runs. This document defines lexical syntax, declarations, statements, literals, and expression precedence. Type rules are in 02-types-and-inference.md.

The Wren revision is pinned to 99d2f0b8fc2686134b32b18166e037639f7e9f2c. Beep references the scanner and Pratt parser organization in [wren_compiler.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_compiler.c), especially Parser, tokenization, parsePrecedence, methodCall, and endCompiler. Beep retains expression parsing and adds a source-spanned AST because type checking precedes emission.

## 2. Source representation

Source is UTF-8. Invalid encoding is a compile error. Source spans store byte offsets. Diagnostics report one-based line and Unicode scalar column. LF, CRLF, and CR each advance one line. Identifier comparison uses exact Unicode scalar sequences, is case-sensitive, and performs no normalization.

Identifiers start with a Unicode letter or underscore and continue with letters, decimal digits, or underscores. Reserved words are as, break, class, construct, continue, else, enum, false, for, from, if, implements, import, in, interface, is, let, match, mut, private, public, return, static, super, this, true, type, var, while, where. Core type names cannot be rebound at module scope.

Line comments begin with //. Block comments use /* and */ and nest. A newline ends a statement unless parsing continues an expression or the parser is within delimiters. Semicolons optionally separate statements.

## 3. Grammar

EBNF braces mean repetition, brackets mean optional, and quoted text is literal syntax. NL is a statement-ending newline after continuation rules.

    module          = { import | declaration } ;
    import          = "import" string ["as" identifier] ["." "{" names "}"] ;
    declaration     = class | interface | enum | record | alias | function | constant | init ;
    class           = visibility "class" name [typeParams] ["is" type {"," type}] classBody ;
    interface       = visibility "interface" name [typeParams] ["is" type {"," type}] interfaceBody ;
    enum            = visibility "enum" name [typeParams] "{" case {"," case} "}" ;
    case            = name ["(" types ")"] ;
    record          = visibility "type" name [typeParams] "{" field+ "}" ;
    alias           = visibility "type" name [typeParams] "=" type ;
    function        = visibility "fn" name [typeParams] parameters [":" type] block ;
    constant        = visibility "let" name [":" type] "=" expression ;
    init            = "init" parameters ":" "Result<Unit, E>" block ;
    classBody       = "{" {field | method | foreignMember} "}" ;
    method          = visibility ["static"] memberSignature [":" type] block ;
    memberSignature = name parameters | name "{" expression "}" | name "=" parameters
                    | operator parameters | "[" types "]" ["=" parameters] ;
    field           = visibility ["final"] ("let" | "var") name ":" type ["=" expression] ;
    parameters      = "(" [parameter {"," parameter}] ")" ;
    parameter       = [label ":"] name ":" type ["=" expression] ;
    typeParams      = "<" typeParam {"," typeParam} ">" ;
    typeParam       = ["in" | "out"] name {":" type} ["=" type] ;
    block           = "{" {statement} [expression] "}" ;
    statement       = local | return | if | while | for | break | continue | expression NL ;
    local           = ("let" | "var") name [":" type] "=" expression NL ;
    if              = "if" "(" expression ")" block ["else" (block | if)] ;
    while           = "while" "(" expression ")" block ;
    for             = "for" "(" name "in" expression ")" block ;
    match           = "match" expression "{" arm+ "}" ;
    arm             = pattern ["if" expression] "->" expression [","] ;
    type            = qualifiedName ["<" types ">"] | "(" types ")" "->" type
                    | "(" types ")" | "Self" | "Never" ;

The implementation must maintain a complete parser grammar for every production. This declaration grammar also requires productions for visibility, names, lists, expressions, types, patterns, operators, foreign declarations, interpolation, and where clauses. The lexer and parser must enforce the same newline continuation rule.

The parser rejects try, try/catch, async, await, yield, Fiber, and dynamic/Any declarations. Interpolation uses %(expression). Associated type equality uses where clauses, for example T: Sequence where T.Element == Byte. Same-name methods with equal arity cannot be overloaded by parameter type.

## 4. Literals

Bool has true and false. Integers use decimal, 0b, 0o, or 0x. Their type is Int unless an expected Byte accepts a value from 0 through 255. Int is signed 64-bit two's-complement. Float is IEEE 754 binary64. Numeric conversion is explicit.

Strings use double quotes and Unicode scalar values. Escapes are backslash, quote, n, r, t, 0, and u{one to six hexadecimal digits}. Invalid escapes and scalar values are compile errors. Interpolation expressions evaluate once, left to right, and require Display. Triple-quoted strings preserve contents and do not process escapes or interpolation.

## 5. Expressions and evaluation order

Precedence from highest to lowest: call/member/subscript; prefix ! - ~; multiplicative; additive; range; shifts; bitwise and; bitwise xor; bitwise or; relational/is; equality; &&; ||; ?:; assignment. Assignment and ?: associate right; other binary operators associate left.

Receiver evaluates before arguments. Arguments evaluate left to right. Assignment evaluates target receiver/index before the assigned expression. && evaluates its right operand only when its left operand is true. || evaluates its right operand only when its left operand is false. These rules preserve Wren call order and short-circuit behavior while requiring Bool.

## 6. Conformance cases

- if (1) {} produces a type diagnostic expecting Bool and finding Int.
- A source file containing try or yield produces a syntax diagnostic at that token.
- A string with two side-effecting interpolation expressions evaluates each once in source order.
- LF and CRLF variants produce identical token kinds and corresponding line/column diagnostics.
- An integer literal outside Int range produces a compile diagnostic and never wraps during parsing.
