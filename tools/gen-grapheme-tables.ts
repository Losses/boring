/**
 * Generates src/reflaxe/unicode/GraphemeBreakData.hx from the pinned
 * Unicode data files in tools/unicode-data/ and validates the merged table
 * against the official UAX #29 conformance file before writing it.
 *
 * Sources (Unicode 17.0.0):
 *   GraphemeBreakProperty.txt  - Grapheme_Cluster_Break classes
 *   emoji-data.txt             - Extended_Pictographic (rule GB11)
 *   DerivedCoreProperties.txt  - Indic_Conjunct_Break (rule GB9c)
 *   GraphemeBreakTest.txt      - boundary conformance vectors
 *
 * The table is one flat int array, three ints per range
 * (start, endInclusive, packed). The packed value carries the
 * Grapheme_Cluster_Break class in bits 0-3, Extended_Pictographic in
 * bit 4, and Indic_Conjunct_Break in bits 5-6. Code points absent from
 * the table are class Other with no flags.
 */

import { parsePropertyFile, parseIncbSections, runConformance } from "./grapheme-table-lib";

const DATA_DIR = import.meta.dir + "/unicode-data";
const OUT_PATH = import.meta.dir + "/../src/reflaxe/unicode/GraphemeBreakData.hx";

const SOURCE_FILES = ["GraphemeBreakProperty", "emoji-data", "DerivedCoreProperties", "GraphemeBreakTest"] as const;

function unicodeVersion(): string {
	const args = process.argv.slice(2);
	const flag = args.indexOf("--fetch");
	if (flag === -1) {
		return "17.0.0";
	}
	const version = args[flag + 1];
	if (version === undefined || !/^\d+\.\d+\.\d+$/.test(version)) {
		throw new Error("--fetch needs a Unicode version like 18.0.0");
	}
	return version;
}

/**
 * Downloads the four source files of one Unicode release into
 * tools/unicode-data/ under version-suffixed names. The download is
 * explicit: ordinary generation reads the pinned files and stays
 * network-free.
 */
async function fetchSources(version: string): Promise<void> {
	const urls: Record<string, string> = {
		GraphemeBreakProperty: `https://unicode.org/Public/${version}/ucd/auxiliary/GraphemeBreakProperty.txt`,
		"emoji-data": `https://unicode.org/Public/${version}/ucd/emoji/emoji-data.txt`,
		DerivedCoreProperties: `https://unicode.org/Public/${version}/ucd/DerivedCoreProperties.txt`,
		GraphemeBreakTest: `https://unicode.org/Public/${version}/ucd/auxiliary/GraphemeBreakTest.txt`,
	};
	for (const name of SOURCE_FILES) {
		const response = await fetch(urls[name]!);
		if (!response.ok) {
			throw new Error(`download failed for ${name}: ${response.status}`);
		}
		const target = `${DATA_DIR}/${name}-${version}.txt`;
		await Bun.write(target, await response.text());
		console.log(`fetched ${target}`);
	}
}

const GCB_CLASS = new Map<string, number>([
	["CR", 1], ["LF", 2], ["Control", 3], ["Extend", 4], ["ZWJ", 5],
	["Regional_Indicator", 6], ["Prepend", 7], ["SpacingMark", 8],
	["L", 9], ["V", 10], ["T", 11], ["LV", 12], ["LVT", 13],
]);
const INCB_VALUE = new Map<string, number>([
	["Consonant", 0x20], ["Linker", 0x40], ["Extend", 0x60],
]);

interface PropertyEntry {
	start: number;
	end: number;
	property: string;
}

interface FieldEvent {
	pos: number;
	field: number;
	value: number;
}

async function main(): Promise<void> {
	const version = unicodeVersion();
	if (process.argv.includes("--fetch")) {
		await fetchSources(version);
	}
	const read = async (name: string): Promise<string> => Bun.file(`${DATA_DIR}/${name}-${version}.txt`).text();
	const gcbText = await read("GraphemeBreakProperty");
	const emojiText = await read("emoji-data");
	const derivedText = await read("DerivedCoreProperties");
	const testText = await read("GraphemeBreakTest");

	// Field slots: 0 Grapheme_Cluster_Break class, 1 Extended_Pictographic,
	// 2 Indic_Conjunct_Break. Ranges within one field never overlap, so the
	// sweep keeps one active value per field and ORs the slots together.
	interface MergedRange {
	start: number;
	end: number;
	packed: number;
}

const events: FieldEvent[] = [];
	const addField = (ranges: PropertyEntry[], field: number, values: Map<string, number>): void => {
		for (const range of ranges) {
			const value = values.get(range.property);
			if (value === undefined) {
				throw new Error(`unknown property for field ${field}: ${range.property}`);
			}
			events.push({ pos: range.start, field, value });
			events.push({ pos: range.end + 1, field, value: 0 });
		}
	};

	addField(parsePropertyFile(gcbText), 0, GCB_CLASS);
	addField(parsePropertyFile(emojiText).filter((r) => r.property === "Extended_Pictographic"), 1, new Map([["Extended_Pictographic", 0x10]]));
	addField(parseIncbSections(derivedText), 2, INCB_VALUE);
	// The property files group ranges by property, not by code point, so a
	// range end and an adjacent range start of the same field can arrive in
	// either order. Clearing before setting at a shared position keeps the
	// active value correct.
	events.sort((a, b) => {
		if (a.pos !== b.pos) {
			return a.pos - b.pos;
		}
		return (a.value === 0 ? 0 : 1) - (b.value === 0 ? 0 : 1);
	});

	const merged: MergedRange[] = [];
	const active = [0, 0, 0];
	let pos = 0;
	let index = 0;
	while (index < events.length) {
		const next = events[index]!.pos;
		if (next > pos) {
			const packed = active[0]! | active[1]! | active[2]!;
			if (packed !== 0) {
				merged.push({ start: pos, end: next - 1, packed });
			}
			pos = next;
		}
		while (index < events.length && events[index]!.pos === pos) {
			const event = events[index]!;
			active[event.field] = event.value;
			index += 1;
		}
	}

	// The last event position is the end of the highest listed range plus
	// one; everything above it stays class Other and needs no entry.
	if (pos > 0x110000) {
		throw new Error(`sweep ended at U+${pos.toString(16)}, past U+10FFFF`);
	}
	for (let i = 1; i < merged.length; i += 1) {
		if (merged[i]!.start <= merged[i - 1]!.end) {
			throw new Error(`overlapping ranges at U+${merged[i]!.start.toString(16)}`);
		}
	}

	const table: number[] = [];
	for (const range of merged) {
		table.push(range.start, range.end, range.packed);
	}

	const failures = runConformance(table, testText);
	if (failures.length > 0) {
		for (const failure of failures.slice(0, 10)) {
			console.error(failure);
		}
		throw new Error(`grapheme walk failed ${failures.length} conformance lines`);
	}

	const lines: string[] = [];
	lines.push("// Generated by tools/gen-grapheme-tables.ts from the pinned Unicode");
	lines.push(`// ${version} data files in tools/unicode-data/. Do not edit by hand;`);
	lines.push("// regenerate with `bun run gen:unicode`.");
	lines.push("package reflaxe.unicode;");
	lines.push("");
	lines.push("/**");
	lines.push("    Flat grapheme break table: three ints per range");
	lines.push("    (start, endInclusive, packed). The packed value carries the");
	lines.push("    Grapheme_Cluster_Break class in bits 0-3 (mask 0x0f),");
	lines.push("    Extended_Pictographic in bit 4 (0x10), and");
	lines.push("    Indic_Conjunct_Break in bits 5-6 (Consonant 0x20,");
	lines.push("    Linker 0x40, Extend 0x60). Absent code points are");
	lines.push("    class Other with no flags. Validated against the Unicode");
	lines.push("    GraphemeBreakTest conformance file at generation time.");
	lines.push("**/");
	lines.push("class GraphemeBreakData {");
	lines.push(`\tpublic static final UNICODE_VERSION:String = "${version}";`);
	lines.push(`\tpublic static final RANGE_COUNT:Int = ${merged.length};`);
	lines.push("\tpublic static final TABLE:Array<Int> = [");
	for (let i = 0; i < table.length; i += 15) {
		lines.push("\t\t" + table.slice(i, i + 15).join(", ") + ",");
	}
	lines.push("\t];");
	lines.push("}");

	await Bun.write(OUT_PATH, lines.join("\n") + "\n");
	console.log(`wrote ${OUT_PATH} (${merged.length} ranges, ${table.length} ints, conformance lines all pass)`);
}

await main();
