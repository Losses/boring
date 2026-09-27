# Beep specifications

Beep is a statically typed language with an embeddable source compiler and virtual machine. Its syntax and runtime structure follow Wren where those choices fit the confirmed Beep rules.

## Normative documents

- [Language overview and grammar](01-language.md)
- [Type system and inference](02-types-and-inference.md)
- [Classes, methods, closures, and patterns](03-objects-and-control.md)
- [Errors and standard library contracts](04-errors-and-library.md)
- [Virtual machine and bytecode](05-vm-bytecode.md)
- [Memory management](06-memory.md)
- [Modules and embedding API](07-modules-embedding.md)
- [Wren source and behavior map](08-wren-reference.md)
- [Lexer and complete expression grammar](09-lexer-expression-grammar.md)
- [Opcode and bytecode reference](10-opcode-reference.md)
- [Embedding ABI data layouts](11-abi-data-layouts.md)
- [Compiler architecture and implementation references](12-compiler-architecture-and-references.md)
- [Implementation plan](implementation-plan.md)

The topic documents are normative as a set. A topic document owns the behavior named by its title. The Wren reference map records adopted and changed behavior with pinned source links. Product choices confirmed by the owner are stated as rules in the relevant topic documents.
