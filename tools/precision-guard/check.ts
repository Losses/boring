#!/usr/bin/env bun
/**
 * Precision guard for the shared test sources.
 *
 * The files under samples/tests compile in the binary64 bundles and in the
 * f32 bundles. A floating point literal that binary64 represents and binary32
 * does not becomes an infinity or a zero in the f32 bundles, and an assertion
 * that uses it then fails for a reason unrelated to the property under test.
 *
 * The guard reads the code positions of the scanned Haxe sources, keeps every
 * numeric literal, rounds the literal with Math.fround (the binary32
 * rounding), and reports each literal whose binary32 result is not finite or
 * is zero while its binary64 result is finite and nonzero.
 *
 * Usage:
 *     bun tools/precision-guard/check.ts             # scan samples/tests
 *     bun tools/precision-guard/check.ts DIR ...     # scan the given roots
 *
 * A literal is exempt when its own line or the comment line directly above it
 * carries the marker "precision-guard: allow" followed by a reason.
 *
 * Exit status: 0 when no un-annotated literal remains, 1 when hits remain.
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, isAbsolute, join, resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "..", "..");
const DEFAULT_ROOT = resolve(REPO_ROOT, "samples/tests");
const ALLOW_MARKER = "precision-guard: allow";
const USAGE = "usage: bun tools/precision-guard/check.ts [DIR|FILE ...]";

/** The two ways a literal leaves the binary32 range. */
type GuardKind = "overflow" | "underflow";

/** One literal whose binary32 rounding changes its meaning. */
type GuardFinding = {
    readonly file: string;
    readonly line: number;
    readonly column: number;
    readonly literal: string;
    readonly binary64: number;
    readonly binary32: number;
    readonly kind: GuardKind;
    readonly text: string;
};

/** Findings and exemptions of one scanned file. */
type FileAnalysis = {
    readonly findings: ReadonlyArray<GuardFinding>;
    readonly exemptions: ReadonlyArray<string>;
    readonly literals: number;
    readonly outOfRange: number;
};

/** A literal candidate with its offset in the masked source. */
type LiteralMatch = {
    readonly text: string;
    readonly index: number;
};

/** A one-based source position. */
type SourcePosition = {
    readonly line: number;
    readonly column: number;
};

type LexFrameKind = "code" | "string" | "line-comment" | "block-comment";

/** One frame of the comment and string masker. */
type LexFrame = {
    kind: LexFrameKind;
    quote: string;
    depth: number;
    interpolation: boolean;
};

const LITERAL_PATTERN = /(?<![\w$.])(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?(?![\w$.])/g;

function newFrame(kind: LexFrameKind): LexFrame {
    return { kind, quote: "", depth: 0, interpolation: false };
}

/**
 * Returns a copy of the source with the text of comments and string literals
 * replaced by spaces. Offsets and line numbers stay valid, so a match in the
 * result is a numeric literal in a code position.
 */
function maskCommentsAndStrings(source: string): string {
    const masked = source.split("");
    const frames: LexFrame[] = [newFrame("code")];
    let index = 0;
    while (index < source.length) {
        const frame = frames[frames.length - 1]!;
        const char = source.charAt(index);
        const next = source.charAt(index + 1);
        if (frame.kind === "line-comment") {
            if (char === "\n") frames.pop();
            else masked[index] = " ";
            index += 1;
            continue;
        }
        if (frame.kind === "block-comment") {
            if (char === "*" && next === "/") {
                masked[index] = " ";
                masked[index + 1] = " ";
                frames.pop();
                index += 2;
                continue;
            }
            if (char !== "\n") masked[index] = " ";
            index += 1;
            continue;
        }
        if (frame.kind === "string") {
            if (char === "\n") {
                frames.pop();
                index += 1;
                continue;
            }
            if (char === "\\") {
                masked[index] = " ";
                if (next !== "\n") masked[index + 1] = " ";
                index += 2;
                continue;
            }
            if (char === frame.quote) {
                masked[index] = " ";
                frames.pop();
                index += 1;
                continue;
            }
            if (char === "$" && next === "{") {
                masked[index] = " ";
                const inner = newFrame("code");
                inner.interpolation = true;
                frames.push(inner);
                index += 1;
                continue;
            }
            masked[index] = " ";
            index += 1;
            continue;
        }
        if (char === "/" && next === "/") {
            masked[index] = " ";
            masked[index + 1] = " ";
            frames.push(newFrame("line-comment"));
            index += 2;
            continue;
        }
        if (char === "/" && next === "*") {
            masked[index] = " ";
            masked[index + 1] = " ";
            frames.push(newFrame("block-comment"));
            index += 2;
            continue;
        }
        if (char === '"' || char === "'") {
            masked[index] = " ";
            const literal = newFrame("string");
            literal.quote = char;
            frames.push(literal);
            index += 1;
            continue;
        }
        if (char === "{") {
            frame.depth += 1;
            index += 1;
            continue;
        }
        if (char === "}") {
            if (frame.interpolation && frame.depth === 0) {
                masked[index] = " ";
                frames.pop();
                index += 1;
                continue;
            }
            frame.depth -= 1;
            index += 1;
            continue;
        }
        index += 1;
    }
    return masked.join("");
}

/** Returns every numeric literal found in a masked source. */
function findLiterals(masked: string): ReadonlyArray<LiteralMatch> {
    const matches: LiteralMatch[] = [];
    LITERAL_PATTERN.lastIndex = 0;
    let match = LITERAL_PATTERN.exec(masked);
    while (match !== null) {
        matches.push({ text: match[0]!, index: match.index });
        match = LITERAL_PATTERN.exec(masked);
    }
    return matches;
}

/** Returns the offset of every line start, with offset 0 for line one. */
function lineStarts(source: string): ReadonlyArray<number> {
    const starts: number[] = [0];
    for (let index = 0; index < source.length; index += 1) {
        if (source.charCodeAt(index) === 10) starts.push(index + 1);
    }
    return starts;
}

/** Maps a source offset to a one-based line and column. */
function locate(starts: ReadonlyArray<number>, offset: number): SourcePosition {
    let low = 0;
    let high = starts.length - 1;
    while (low < high) {
        const middle = Math.ceil((low + high) / 2);
        if ((starts[middle] ?? 0) <= offset) low = middle;
        else high = middle - 1;
    }
    return { line: low + 1, column: offset - (starts[low] ?? 0) + 1 };
}

/** Reads one file and classifies each of its literals. */
function analyzeFile(path: string): FileAnalysis {
    const source = readFileSync(path, "utf8");
    const masked = maskCommentsAndStrings(source);
    const starts = lineStarts(source);
    const lines = source.split("\n");
    const findings: GuardFinding[] = [];
    const exemptions: string[] = [];
    let literals = 0;
    let outOfRange = 0;
    for (const match of findLiterals(masked)) {
        const value = Number(match.text);
        if (Number.isNaN(value)) continue;
        literals += 1;
        const binary32 = Math.fround(value);
        let kind: GuardKind | undefined = undefined;
        if (!Number.isFinite(binary32)) kind = "overflow";
        else if (value !== 0 && binary32 === 0) kind = "underflow";
        if (kind === undefined) continue;
        outOfRange += 1;
        const position = locate(starts, match.index);
        const text = lines[position.line - 1] ?? "";
        const above = lines[position.line - 2] ?? "";
        const finding: GuardFinding = {
            file: path,
            line: position.line,
            column: position.column,
            literal: match.text,
            binary64: value,
            binary32,
            kind,
            text,
        };
        if (text.includes(ALLOW_MARKER) || above.includes(ALLOW_MARKER)) {
            exemptions.push(`${finding.file}:${finding.line}:${finding.column}: ${finding.literal} [${finding.kind}]`);
        } else {
            findings.push(finding);
        }
    }
    return { findings, exemptions, literals, outOfRange };
}

/** Collects the Haxe files below a root, or the root itself when it is one. */
function collectFiles(root: string): ReadonlyArray<string> {
    const stat = statSync(root, { throwIfNoEntry: false });
    if (stat === undefined) return [];
    if (stat.isFile()) return extname(root) === ".hx" ? [root] : [];
    const files: string[] = [];
    for (const entry of readdirSync(root, { withFileTypes: true })) {
        const path = join(root, entry.name);
        if (entry.isDirectory()) files.push(...collectFiles(path));
        else if (entry.isFile() && extname(entry.name) === ".hx") files.push(path);
    }
    return files;
}

/** Renders a path relative to the repository when it lives inside it. */
function shownPath(path: string): string {
    return path.startsWith(REPO_ROOT) ? path.slice(REPO_ROOT.length + 1) : path;
}

function main(args: ReadonlyArray<string>): number {
    if (args.includes("--help") || args.includes("-h")) {
        console.log(USAGE);
        return 0;
    }
    const roots = (args.length === 0 ? [DEFAULT_ROOT] : args).map((arg) =>
        isAbsolute(arg) ? arg : resolve(process.cwd(), arg),
    );
    const files = [...new Set(roots.flatMap((root) => collectFiles(root)))].sort();
    if (files.length === 0) {
        console.log(`precision guard: no Haxe file found under ${roots.map(shownPath).join(", ")}`);
        return 1;
    }
    const findings: GuardFinding[] = [];
    const exemptions: string[] = [];
    let literals = 0;
    let outOfRange = 0;
    for (const file of files) {
        const analysis = analyzeFile(file);
        findings.push(...analysis.findings);
        exemptions.push(...analysis.exemptions);
        literals += analysis.literals;
        outOfRange += analysis.outOfRange;
    }
    console.log(`precision guard: roots ${roots.map(shownPath).join(", ")}`);
    console.log(`scanned ${files.length} file(s), ${literals} numeric literal(s), ${outOfRange} outside the binary32 range`);
    for (const exemption of exemptions) console.log(`allowed: ${exemption}`);
    for (const finding of findings) {
        console.log(
            `FAIL ${shownPath(finding.file)}:${finding.line}:${finding.column}: ${finding.literal} [${finding.kind}] ` +
                `binary64=${finding.binary64} binary32=${finding.binary32}`,
        );
        console.log(`     ${finding.text.trim()}`);
        console.log(
            `     Use a literal that binary32 represents, or mark the line with "${ALLOW_MARKER} <reason>".`,
        );
    }
    if (findings.length > 0) {
        console.log(`precision guard: ${findings.length} un-annotated literal(s) fail the binary32 range check`);
        return 1;
    }
    console.log("precision guard: every literal stays inside the binary32 range");
    return 0;
}

process.exit(main(process.argv.slice(2)));
