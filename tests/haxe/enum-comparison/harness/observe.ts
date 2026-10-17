import * as path from "node:path";
import { pathToFileURL } from "node:url";

/**
    Host harness for the generated TypeScript tree of the enum comparison
    fixture. The harness loads one generated tree named on its command
    line, calls the generated accessors, table reads, equality reads, and
    the generated comparator, and prints one line per read. It constructs
    no record, builds no table, and holds no expectation about the
    generated behavior; the expected values live in the runner.
*/

/** One generated record value. The harness reads it only as an operand. */
type RecordValue = object;

/** The generated comparator of the record under test. */
type RecordComparator = (left: RecordValue, right: RecordValue) => number;

/** A generated accessor that constructs one record value. */
type RecordSource = () => RecordValue;

/** A generated table read. */
type TableRead = () => string;

/** A generated record equality read. */
type EqualityRead = () => boolean;

/** The generated members of the subject module. */
interface GeneratedMembers {
    keyFirst: RecordSource;
    keyFirstAgain: RecordSource;
    keySecond: RecordSource;
    mapDistinctTags: TableRead;
    eqDistinctTags: EqualityRead;
}

/** The generated members the harness calls. */
interface GeneratedSubject {
    EnumComparisonSubject: GeneratedMembers;
    compareRankKey: RecordComparator;
}

async function loadSubject(tree: string): Promise<GeneratedSubject> {
    const modulePath = path.join(tree, "enumcomparison", "EnumComparisonSubject.ts");
    const loaded: unknown = await import(pathToFileURL(modulePath).href);
    return loaded as GeneratedSubject;
}

const tree = process.argv[2];
if (tree === undefined) {
    console.error("usage: bun tests/haxe/enum-comparison/harness/observe.ts <generated-tree>");
    process.exit(2);
}
const subject = await loadSubject(tree);
const ops = subject.EnumComparisonSubject;

console.log("[host] tree " + tree);
console.log("mapDistinctTags=" + ops.mapDistinctTags());
console.log("eqDistinctTags=" + ops.eqDistinctTags());
console.log("compareKeyFirstKeyFirstAgain=" + subject.compareRankKey(ops.keyFirst(), ops.keyFirstAgain()));
console.log("compareKeyFirstKeySecond=" + subject.compareRankKey(ops.keyFirst(), ops.keySecond()));

