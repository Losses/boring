# Classes, methods, closures, and patterns

## 1. Wren baseline

Wren defines class/member forms in the [Classes guide](https://wren.io/classes.html) and compiles signatures in [wren_compiler.c](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_compiler.c). Runtime classes and instances are created by [wrenNewClass, wrenBindSuperclass, and wrenNewInstance](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.c). Wren uses one superclass and method signatures based on name and arity. Beep retains these forms and checks signatures statically.

## 2. Class declarations and layout

A class has at most one superclass; absent a base it extends Object. Interfaces constrain types and do not occupy class layout. Inheritance is acyclic. Field layout places base fields first, then fields declared by each subclass in source order. Each field has a static type and an initialization bit during construction. The verifier checks offset, declaring class, and field type.

Class member tables are fixed after atomic module installation. Source cannot add or replace members during execution. An instance stores class id and field vector. Class ids are VM-local; bytecode refers to module type records mapped to runtime ids at install.

## 3. Methods and dispatch

A signature includes dispatch kind, name/operator, labels, and arity. Wren permits different arities for one name. Beep preserves this rule and rejects duplicate same-name/same-arity declarations regardless of parameter types. Static checking verifies the unique signature.

Receiver and arguments evaluate left to right. Compiler emits method symbol and signature id. Virtual calls use verified class method table. Static, final, and private methods may use direct slots. super starts lookup at direct base class. Override syntax follows Wren without a required override keyword. Checker requires equal parameter types and permits covariant result. Static methods are not virtual.

Getters omit parentheses. Zero-argument methods use (). Setters use name=(value) and assignment-call syntax. Prefix/infix operators and subscript get/set use Wren signature forms. Parser distinguishes getter and zero-argument method and distinguishes subscript get/set.

In an instance method, parameters and locals resolve before implicit self-send. Unresolved lowercase name without arguments resolves to getter or zero-argument method on this. With arguments, resolution uses name and arity. Uppercase names resolve lexically or at module scope. this.name always selects receiver member. Unresolved names are compile errors. Closures nested in instance methods capture this.

## 4. Constructors and fields

A constructor is construct name(parameters). There is no implicit public constructor. Construction allocates storage, initializes the base, evaluates field initializers in declaration order, executes selected initializer, and publishes instance after all fields initialize. Every normal constructor exit requires initialized fields. A constructor cannot return a replacement object. Fallible factory methods return Result<Self,E>.

Fields are private unless exposed by methods/getters/setters. let fields are immutable after construction; var fields are mutable. Subclasses cannot access private base fields. this is valid in instance methods, constructors, and nested closures. super is valid in subclass instance methods and constructors. Static methods have no receiver.

## 5. Interfaces and witness tables

A class declares explicit interface conformance. Type checker validates methods, properties, associated bindings. Compiler emits one witness table per conformance. A slot contains method id and generic substitution. Verifier checks signature, receiver, result, and projection mapping.

Default methods are inherited when one implementation is unambiguous. Conflicting defaults require a class implementation. Overlapping conformance is rejected before execution. Core interfaces are defined in 04-errors-and-library.md.

## 6. Closures and block arguments

Wren ObjClosure and ObjUpvalue are defined in [wren_value.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.h). Wren captures stack slots and closes upvalues as frames return. Beep represents captured mutable bindings by heap cells shared by all closures. Immutable captures may be copied or stored in cells. A closure retains cells and this after the defining frame returns.

A trailing Wren block argument is syntax sugar for a function literal in the final parameter. Its function type must match. Blocks execute synchronously and cannot suspend.

## 7. Enums, records, tuples, matching

Enums are closed tagged sums. Tags follow declaration order within a compiled module. Payload fields have declared types. Records are structural immutable values keyed by ordered field-name/type pairs. Tuples are structural ordered values.

match evaluates scrutinee once and tests arms in source order. Patterns: wildcard, immutable binding, Bool/integer/string literal, tuple, record, enum case, None, Some, Ok, Err, and class subtype test. Guards have Bool type and execute after pattern success. Guarded arms establish exhaustiveness only when guard is literal true.

Closed enums, Bool, Option, and Result matches cover every case. Diagnostics list missing constructors. Duplicate or unreachable unguarded patterns fail. Class patterns narrow to representable intersections proved by declared inheritance/interfaces.

## 8. Loops and returns

if/while conditions and guards require Bool. for evaluates sequence once and obtains iterator through Sequence. Iterator.next returns Some(element) repeatedly and then None permanently. break/continue target innermost loop. Loops execute synchronously.

Expression blocks return the tail expression. Statement blocks fall through with Unit. Non-Unit functions return on every reachable path. Never terminates the current path. Constructor bare return means successful completion after field checks.

## 9. Acceptance tests

- Base field offsets remain unchanged when subclass fields are added.
- Different arities select distinct Wren signatures.
- Same-name/same-arity declarations with different parameter types fail as duplicates.
- Override retains Wren syntax and rejects incompatible types.
- Getter differs from zero-argument method.
- Setter evaluates receiver and assigned expression once in order.
- Escaping closure shares mutated captured local after outer return.
- Closure retains this through forced GC.
- Witness dispatch invokes statically selected implementation.
- Conflicting defaults and overlapping conformances fail before install.
- Enum, Option, Result, and Bool coverage names missing cases.
- Iterator returns permanent None after exhaustion.
