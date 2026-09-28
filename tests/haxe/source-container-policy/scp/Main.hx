package scp;

import std.Console;
import std.Process;

/**
    Runner of the container fact cases. The expectation table below is
    authored independently of the analyzer's traversal: each row states what
    the written source spelling means, what the three legacy adapters must
    answer, and what element the analyzer's typed face carries.

    The program compares every observed record against this table, prints
    each row, and exits nonzero on any mismatch. Ordinary compilation of this
    fixture finishing is part of the evidence; the macro that observes the
    production queries never exits the compiler.
**/
class Main {
    static var failures:Int = 0;
    static var passes:Int = 0;

    /** The observed records, produced at compile time from the authored
        declarations and the labelled synthetic handles. */
    public static final observed:Array<ObservedCase> = SourceObserver.observeCases();

    static function main():Void {
        for (row in expected()) {
            check(row);
        }
        // Records without an authored expectation are listed as evidence;
        // their spelling is host determined, so the expectation table does
        // not pin them.
        for (record in observed) {
            if (!declared(record.name)) {
                Console.log('observed ${record.name} [${record.label}] wrapper=${record.wrapper} face=${record.face} element=${record.element}');
            }
        }
        if (failures > 0) {
            Console.log('$failures container fact mismatch(es)');
            Process.exit(1);
        }
        Console.log('all $passes container fact rows matched');
    }

    static function check(row:ExpectedCase):Void {
        final found = find(row.name);
        if (found == null) {
            failures++;
            Console.log('FAIL ${row.name}: no observed record');
            return;
        }
        var mismatch = "";
        if (found.label != row.label)
            mismatch += ' label=${found.label}';
        if (row.label == "authored" && found.phase != "macro-expansion-with-typed-class")
            mismatch += ' authoredPhase=${found.phase}';
        if (found.mutable != row.mutable)
            mismatch += ' mutable=${found.mutable}';
        if (found.readOnly != row.readOnly)
            mismatch += ' readOnly=${found.readOnly}';
        if (found.element != row.element)
            mismatch += ' element=${found.element}';
        if (found.wrapper != row.wrapper)
            mismatch += ' wrapper=${found.wrapper}';
        if (found.face != row.face)
            mismatch += ' face=${found.face}';
        if (found.analyzedElement != row.analyzedElement)
            mismatch += ' analyzedElement=${found.analyzedElement}';
        if (row.name == "monoPending" && (found.phase != "before-Context.unify" || found.inputForm != "TMono"))
            mismatch += ' pendingObservation=${found.phase}/${found.inputForm}';
        if (row.name == "monoResolved" && (found.phase != "after-Context.unify" || found.inputForm != "TMono"))
            mismatch += ' resolvedObservation=${found.phase}/${found.inputForm}';
        if (mismatch.length == 0) {
            passes++;
            Console.log('pass ${row.name} ${row.face}');
            return;
        }
        failures++;
        Console.log('FAIL ${row.name}:$mismatch');
    }

    static function declared(name:String):Bool {
        for (row in expected()) {
            if (row.name == name) {
                return true;
            }
        }
        return false;
    }

    static function find(name:String):Null<ObservedCase> {
        for (record in observed) {
            if (record.name == name) {
                return record;
            }
        }
        return null;
    }

    /**
        Authored expectations. `element` is the legacy adapter answer and
        `analyzedElement` the element of the analyzer face; both are display
        labels compared for evidence only.
    **/
    static function expected():Array<ExpectedCase> {
        final rows:Array<ExpectedCase> = [
            {
                name: "directArray",
                label: "authored",
                mutable: true,
                readOnly: false,
                element: "Int",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "aliasedArray",
                label: "authored",
                mutable: true,
                readOnly: false,
                element: "Int",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "genericAliasArray",
                label: "authored",
                mutable: true,
                readOnly: false,
                element: "Int",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "nestedAliasArray",
                label: "authored",
                mutable: true,
                readOnly: false,
                element: "Float",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Float)",
                analyzedElement: "Float"
            },
            {
                name: "directReadOnly",
                label: "authored",
                mutable: false,
                readOnly: true,
                element: "String",
                wrapper: "NoExplicitWrapper",
                face: "ReadOnlyArrayFace(String)",
                analyzedElement: "String"
            },
            {
                name: "aliasedReadOnly",
                label: "authored",
                mutable: false,
                readOnly: true,
                element: "String",
                wrapper: "NoExplicitWrapper",
                face: "ReadOnlyArrayFace(String)",
                analyzedElement: "String"
            },
            {
                name: "outerNullArray",
                label: "authored",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "ExplicitOuterNull(Array<Int>)",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "outerNullReadOnly",
                label: "authored",
                mutable: false,
                readOnly: true,
                element: null,
                wrapper: "ExplicitOuterNull(std.ReadOnlyArray<String>)",
                face: "ReadOnlyArrayFace(String)",
                analyzedElement: "String"
            },
            {
                name: "elementNullArray",
                label: "authored",
                mutable: true,
                readOnly: false,
                element: "Null<String>",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Null<String>)",
                analyzedElement: "Null<String>"
            },
            {
                name: "scalar",
                label: "authored",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "NoExplicitWrapper",
                face: "OtherSourceType",
                analyzedElement: null
            },
            {
                name: "aliasedScalar",
                label: "authored",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "NoExplicitWrapper",
                face: "OtherSourceType",
                analyzedElement: null
            },
            {
                name: "foreignReadOnly",
                label: "authored",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "NoExplicitWrapper",
                face: "OtherSourceType",
                analyzedElement: null
            },
            {
                name: "foreignAliasReadOnly",
                label: "authored",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "NoExplicitWrapper",
                face: "OtherSourceType",
                analyzedElement: null
            },
            {
                name: "foreignArray",
                label: "authored",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "NoExplicitWrapper",
                face: "OtherSourceType",
                analyzedElement: null
            },
            {
                name: "chainArray",
                label: "authored",
                mutable: true,
                readOnly: false,
                element: "Int",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "longChainArray",
                label: "authored",
                mutable: true,
                readOnly: false,
                element: "Int",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "chainResolved",
                label: "synthetic-chain",
                mutable: true,
                readOnly: false,
                element: "Int",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "lazyReadOnly",
                label: "synthetic-lazy",
                mutable: false,
                readOnly: true,
                element: "String",
                wrapper: "NoExplicitWrapper",
                face: "ReadOnlyArrayFace(String)",
                analyzedElement: "String"
            },
            {
                name: "lazyFailure",
                label: "synthetic-lazy-failure",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "WrapperUnresolved(LazyResolutionFailed)",
                face: "UnresolvedSource(LazyResolutionFailed)",
                analyzedElement: null
            },
            {
                name: "lazyCycle",
                label: "synthetic-lazy-cycle",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "WrapperUnresolved(CycleDetected)",
                face: "UnresolvedSource(CycleDetected)",
                analyzedElement: null
            },
            {
                name: "nullInput",
                label: "synthetic-null",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "WrapperUnresolved(NullTypeInput)",
                face: "UnresolvedSource(NullTypeInput)",
                analyzedElement: null
            },
            {
                name: "outerNullLazyFailure",
                label: "synthetic-outer-null-lazy-failure",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "ExplicitOuterNull(TLazy)",
                face: "UnresolvedSource(LazyResolutionFailed)",
                analyzedElement: null
            },
            {
                name: "monoPending",
                label: "synthetic-mono-pending",
                mutable: false,
                readOnly: false,
                element: null,
                wrapper: "WrapperUnresolved(PendingMonomorph)",
                face: "UnresolvedSource(PendingMonomorph)",
                analyzedElement: null
            },
            {
                name: "monoResolved",
                label: "synthetic-mono-resolved",
                mutable: true,
                readOnly: false,
                element: "Int",
                wrapper: "NoExplicitWrapper",
                face: "MutableArray(Int)",
                analyzedElement: "Int"
            },
            {
                name: "firstMutableQuery",
                label: "synthetic-adapter-first",
                mutable: false,
                readOnly: true,
                element: "String",
                wrapper: "NoExplicitWrapper",
                face: "ReadOnlyArrayFace(String)",
                analyzedElement: "String"
            },
            {
                name: "firstReadOnlyQuery",
                label: "synthetic-adapter-first",
                mutable: false,
                readOnly: true,
                element: "String",
                wrapper: "NoExplicitWrapper",
                face: "ReadOnlyArrayFace(String)",
                analyzedElement: "String"
            },
            {
                name: "firstElementQuery",
                label: "synthetic-adapter-first",
                mutable: false,
                readOnly: true,
                element: "String",
                wrapper: "NoExplicitWrapper",
                face: "ReadOnlyArrayFace(String)",
                analyzedElement: "String"
            }
        ];
        return rows;
    }
}

typedef ExpectedCase = {
    final name:String;
    final label:String;
    final mutable:Bool;
    final readOnly:Bool;
    final element:Null<String>;
    final wrapper:String;
    final face:String;
    final analyzedElement:Null<String>;
}
