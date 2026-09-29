// Runtime check for the generated NullableShapes module. Haxe semantics:
// a null instance-call receiver throws; an omitted trailing optional
// constructor argument folds to null.
import { pathToFileURL } from "node:url";

type WidgetLike = {
    tagged: () => string;
};

type BoxLike = {
    hasLabel: () => boolean;
};

type WidgetClass = {
    new (label: string): WidgetLike;
};

type BoxClass = {
    new (label?: string | null): BoxLike;
    prototype: BoxLike & { constructor: BoxClass };
};

type FaultClass = {
    new (detail?: string | null): BoxLike & { detail: string | null; message: string };
};

type MixerLike = {
    suffixText: () => string;
    adoptedTagged: (widget: WidgetLike | null) => string;
};

type MixerClass = {
    new (source: string, suffix?: string | null): MixerLike;
};

type ChildFaultLike = {
    code: string | null;
    extra: string;
    message: string;
};

type ChildFaultClass = {
    new (extra: string, code?: string): ChildFaultLike;
};

type NullableShapesModule = {
    Widget: WidgetClass;
    Box: BoxClass;
    ShapeFault: FaultClass;
    Mixer: MixerClass;
    ChildFault: ChildFaultClass;
    NullableShapes: {
        tagged: (widget: WidgetLike | null) => string;
        taggedGuarded: (widget: WidgetLike | null) => string;
        taggedCoalesced: (a: WidgetLike | null, b: WidgetLike | null) => string;
        taggedAtIndex: (widgets: Array<WidgetLike>, index: number) => string;
    };
};

const modulePath = process.argv[2];
if (modulePath == null) {
    console.error("usage: bun check.ts <generated NullableShapes.ts>");
    process.exit(2);
}
const loaded = await import(pathToFileURL(modulePath).href);
const generated = loaded as Partial<NullableShapesModule>;
if (generated.Widget == null || generated.Box == null || generated.ShapeFault == null || generated.Mixer == null || generated.ChildFault == null
    || generated.NullableShapes == null) {
    console.error("generated module exposes none of Widget, Box, ShapeFault, Mixer, ChildFault, NullableShapes");
    process.exit(2);
}

let failures = 0;
function expectEqual(name: string, actual: unknown, expected: unknown): void {
    if (actual !== expected) {
        failures += 1;
        console.error(name + " mismatch: expected " + JSON.stringify(expected)
            + ", actual " + JSON.stringify(actual));
    }
}

const widget = new generated.Widget("a");
expectEqual("tagged(normal)", generated.NullableShapes.tagged(widget), "[a]");

let threw: unknown = null;
try {
    generated.NullableShapes.tagged(null);
} catch (problem) {
    threw = problem;
}
if (threw == null) {
    failures += 1;
    console.error("tagged(null) did not throw on the null receiver");
} else {
    console.log("tagged(null) threw as Haxe requires");
}

const emptyBox = new generated.Box();
expectEqual("omitted argument", emptyBox.hasLabel(), false);
const nullBox = new generated.Box(null);
expectEqual("explicit null", nullBox.hasLabel(), false);
const valuedBox = new generated.Box("x");
expectEqual("non-null value", valuedBox.hasLabel(), true);

const faultEmpty = new generated.ShapeFault();
expectEqual("fault omitted super fold", faultEmpty.detail, null);
expectEqual("fault message", faultEmpty.message, "shape fault");
const faultValued = new generated.ShapeFault("d");
expectEqual("fault valued detail", faultValued.detail, "d");
expectEqual("fault valued message", faultValued.message, "shape fault");

const mixerEmpty = new generated.Mixer("s");
expectEqual("mixer omitted fold", mixerEmpty.suffixText(), "ss");
const mixerValued = new generated.Mixer("s", "!");
expectEqual("mixer explicit value", mixerEmpty === mixerValued ? false : mixerValued.suffixText(), "s!");
const mixerBlank = new generated.Mixer("s", "");
expectEqual("mixer blank suffix", mixerBlank.suffixText(), "s");
const mixerHolder = new generated.Mixer("q");
expectEqual("anon object receiver", mixerHolder.adoptedTagged.call(mixerHolder, widget), "[a]");

expectEqual("guarded normal", generated.NullableShapes.taggedGuarded(widget), "[a]");
expectEqual("guarded null", generated.NullableShapes.taggedGuarded(null), "none");
expectEqual("coalesced first", generated.NullableShapes.taggedCoalesced(widget, null), "[a]");
expectEqual("coalesced second", generated.NullableShapes.taggedCoalesced(null, widget), "[a]");
expectEqual("indexed receiver", generated.NullableShapes.taggedAtIndex([widget], 0), "[a]");

let coalesceThrew: unknown = null;
try {
    generated.NullableShapes.taggedCoalesced(null, null);
} catch (problem) {
    coalesceThrew = problem;
}
if (coalesceThrew == null) {
    failures += 1;
    console.error("taggedCoalesced(null, null) did not throw on the null receiver");
} else {
    console.log("taggedCoalesced(null, null) threw as Haxe requires");
}

const childEmpty = new generated.ChildFault("e");
expectEqual("forwarded omitted super fold", childEmpty.message, "fault:?");
expectEqual("forwarded omitted code", childEmpty.code, null);
expectEqual("forwarded own field", childEmpty.extra, "e");
const childValued = new generated.ChildFault("e", "k");
expectEqual("forwarded valued super arg", childValued.message, "fault:k");
expectEqual("forwarded valued code", childValued.code, "k");

if (failures > 0) {
    console.error("NULLABLE LOWERING FAIL: " + failures + " mismatch(es)");
    process.exit(1);
}
console.log("NULLABLE LOWERING PASS");
