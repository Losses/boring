/**
 * Shared parsing and UAX #29 reference logic for the grapheme break table.
 * Used by tools/gen-grapheme-tables.ts at generation time and by the data
 * conformance test in tests/ts/, which re-reads the generated Haxe table
 * and re-runs the official Unicode GraphemeBreakTest vectors.
 *
 * The walk implements extended grapheme cluster boundaries (UAX #29):
 * GB3, GB4, GB5, GB6-GB8, GB9, GB9a, GB9b, GB9c, GB11, GB12/13, GB999.
 * Rules GB11 and GB9c need link state carried across the walk; GB12/13
 * need regional-indicator parity. The walk is written over UTF-16 code
 * units because that is the storage of three of the four targets; the
 * Rust lane walks UTF-32 chars with the same decisions.
 */

export interface PropertyRange {
	start: number;
	end: number;
	property: string;
}

/** Parses `00A9..00AE ; Property # comment` lines from a UCD property file. */
export function parsePropertyFile(text: string): PropertyRange[] {
	const ranges: PropertyRange[] = [];
	for (const line of text.split("\n")) {
		const stripped = line.split("#")[0]!.trim();
		if (stripped.length === 0) {
			continue;
		}
		const match = /^([0-9A-Fa-f]+)(?:\.\.([0-9A-Fa-f]+))?\s*;\s*(.+?)\s*$/.exec(stripped);
		if (match === null) {
			continue;
		}
		const start = parseInt(match[1]!, 16);
		const end = match[2] !== undefined ? parseInt(match[2], 16) : start;
		ranges.push({ start, end, property: match[3]! });
	}
	return ranges;
}

/**
 * Parses the Indic_Conjunct_Break sections of DerivedCoreProperties.txt.
 * Lines carry `; InCB; Value`, so the property arrives in two fields; the
 * section header supplies the active property name.
 */
export function parseIncbSections(text: string): PropertyRange[] {
	const ranges: PropertyRange[] = [];
	let current: string | null = null;
	for (const line of text.split("\n")) {
		const header = /^#\s*Indic_Conjunct_Break=(Consonant|Linker|Extend)\s*$/.exec(line.trim());
		if (header !== null) {
			current = header[1]!;
			continue;
		}
		if (current === null) {
			continue;
		}
		const stripped = line.split("#")[0]!.trim();
		if (stripped.length === 0) {
			continue;
		}
		const match = /^([0-9A-Fa-f]+)(?:\.\.([0-9A-Fa-f]+))?\s*;\s*InCB;\s*(Consonant|Linker|Extend)\s*$/.exec(stripped);
		if (match === null) {
			if (stripped.includes(";")) {
				current = null;
			}
			continue;
		}
		const start = parseInt(match[1]!, 16);
		const end = match[2] !== undefined ? parseInt(match[2], 16) : start;
		ranges.push({ start, end, property: match[3]! });
	}
	return ranges;
}

export function lookupPacked(table: number[], code: number): number {
	let lo = 0;
	let hi = Math.floor(table.length / 3) - 1;
	while (lo <= hi) {
		const mid = (lo + hi) >> 1;
		const base = mid * 3;
		if (code < table[base]!) {
			hi = mid - 1;
		} else if (code > table[base + 1]!) {
			lo = mid + 1;
		} else {
			return table[base + 2]!;
		}
	}
	return 0;
}

interface WalkState {
	pict: number;
	incb: number;
	riOdd: boolean;
}

/** Decides the boundary before `cur`; the state still describes the text before it. */
function breaksBefore(prev: number, cur: number, state: WalkState): boolean {
	const pc = prev & 0x0f;
	const cc = cur & 0x0f;
	if (pc === 1 && cc === 2) return false;                                             // GB3 CR x LF
	if (pc === 1 || pc === 2 || pc === 3) return true;                                 // GB4
	if (cc === 1 || cc === 2 || cc === 3) return true;                                 // GB5
	if (pc === 9 && (cc === 9 || cc === 10 || cc === 12 || cc === 13)) return false;   // GB6
	if ((pc === 10 || pc === 12) && (cc === 10 || cc === 11)) return false;            // GB7
	if ((pc === 11 || pc === 13) && cc === 11) return false;                           // GB8
	if (cc === 4 || cc === 5) return false;                                            // GB9
	if (cc === 8) return false;                                                        // GB9a
	if (pc === 7) return false;                                                        // GB9b
	if ((cur & 0x20) !== 0 && state.incb === 2) return false;                          // GB9c
	if ((cur & 0x10) !== 0 && state.pict === 2) return false;                          // GB11
	if (cc === 6 && state.riOdd) return false;                                         // GB12/13
	return true;                                                                       // GB999
}

/**
 * Advances the link states and the regional-indicator parity past `cur`.
 * GB11 arms only while the text ends in ExtPict Extend* ZWJ, so an Extend
 * after the ZWJ clears it; GB9c arms after Consonant then Extend/Linker
 * runs that contain at least one Linker.
 */
function advanceState(cur: number, state: WalkState): void {
	const cc = cur & 0x0f;
	if ((cur & 0x10) !== 0) {
		state.pict = 1;
	} else if (cc === 5) {
		state.pict = state.pict === 1 ? 2 : 0;
	} else if (cc === 4) {
		if (state.pict !== 1) {
			state.pict = 0;
		}
	} else {
		state.pict = 0;
	}
	const incb = cur & 0x60;
	if (incb === 0x20) {
		state.incb = 1;
	} else if (incb === 0x40) {
		state.incb = state.incb >= 1 ? 2 : 0;
	} else if (incb === 0x60) {
		// Extend keeps the consonant context alive.
	} else {
		state.incb = 0;
	}
	state.riOdd = cc === 6 ? !state.riOdd : false;
}

/**
 * Walks the string and reports, for every code point, whether a cluster
 * boundary sits before it. The first code point always reports true (GB1).
 */
export function breakFlags(table: number[], s: string): boolean[] {
	const flags: boolean[] = [];
	const state: WalkState = { pict: 0, incb: 0, riOdd: false };
	let prev = -1;
	let unit = 0;
	while (unit < s.length) {
		const code = s.codePointAt(unit) as number;
		const packed = lookupPacked(table, code);
		flags.push(prev < 0 || breaksBefore(prev, packed, state));
		advanceState(packed, state);
		prev = packed;
		unit += code > 0xffff ? 2 : 1;
	}
	return flags;
}

/**
 * Runs the official GraphemeBreakTest vectors against the table.
 * Each line lists code points with the expected boundary mark before
 * every one of them. Returns one message per failing line.
 */
export function runConformance(table: number[], testText: string): string[] {
	const failures: string[] = [];
	for (const line of testText.split("\n")) {
		const body = line.split("#")[0]!.trim();
		if (body.length === 0) {
			continue;
		}
		const tokens = body.split(/\s+/);
		const codes: number[] = [];
		const expected: boolean[] = [];
		for (const token of tokens) {
			if (token === "÷") {
				expected.push(true);
			} else if (token === "×") {
				expected.push(false);
			} else {
				codes.push(parseInt(token, 16));
			}
		}
		// The line starts with a mark before the first code point and ends
		// with the end-of-text mark (GB2), so marks outnumber codes by one.
		if (codes.length === 0 || expected.length !== codes.length + 1) {
			failures.push(`malformed line: ${line}`);
			continue;
		}
		expected.pop();
		const text = codes.map((c) => String.fromCodePoint(c)).join("");
		const actual = breakFlags(table, text);
		for (let i = 0; i < codes.length; i += 1) {
			if (actual[i] !== expected[i]!) {
				failures.push(`line ${line.trim()}: boundary before U+${codes[i]!.toString(16).toUpperCase()} expected ${expected[i]!} got ${actual[i]!}`);
				break;
			}
		}
	}
	return failures;
}
