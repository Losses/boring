package reflaxe.unicode;

#if macro
import haxe.crypto.Md5;
import haxe.macro.Context;
import haxe.macro.Expr;
import runtime.GraphemeWalk;

/**
    Compile-time pipeline for the grapheme break table
    (docs/specs/stdlib/11-grapheme-clusters.md).

    At compilation start this module reads the pinned Unicode data files
    from `tools/unicode-data/`, merges them into the flat range table,
    and gates the merge on the official GraphemeBreakTest conformance
    vectors run through the shared walk in `runtime.GraphemeWalk`.
    The one consumer is `tableField()`: the `:build` macro on
    `runtime.Graphemes` injects the table as a static field, and that
    resident module compiles into every target's runtime package.

    Nothing generated is committed. A content-hash cache under `out/`
    keeps ordinary compilations free of parsing and conformance: the
    cache key is the hash of the four input files, so any change to the
    pinned data re-runs the full gate.

    `-D fetch-unicode=<version>` downloads the four files of that
    Unicode release from unicode.org before parsing, which is the
    refresh path to a later release. Ordinary compilation stays
    network-free and reads the pinned files.
**/
typedef PropertyRange = {
    start:Int,
    end:Int,
    property:String,
};

typedef FieldEvent = {
    pos:Int,
    field:Int,
    value:Int,
};

class GraphemeData {
    /** The Unicode release pinned in tools/unicode-data. */
    static final PINNED_VERSION:String = "17.0.0";

    static final SOURCE_FILES:Array<String> = [
        "GraphemeBreakProperty",
        "emoji-data",
        "DerivedCoreProperties",
        "GraphemeBreakTest",
    ];

    static var cachedTable:Null<Array<Int>> = null;
    static var cachedVersion:Null<String> = null;

    /**
        Build macro for the resident runtime module: injects the merged
        table as one constant `Array<Int>` field, the same shape the
        compile-time data-table mechanism renders natively on every
        target (docs/specs/features/20-compile-time-data-tables.md).
        Typing the class runs the full pipeline: merge, conformance
        gate, then injection. The conformance walk lives in
        `runtime.GraphemeWalk`, a plain class with no build macro, so
        the gate never re-enters this pipeline.
    **/
    public static function tableField(fieldName:String):Array<Field> {
        final table = table();
        final entries:Array<Expr> = [for (v in table) macro $v{v}];
        return Context.getBuildFields().concat([
            {
                name: fieldName,
                doc: "Flat grapheme break table: three ints per range (start, endInclusive, packed). Validated against the Unicode GraphemeBreakTest conformance file at compilation start.",
                access: [APublic, AStatic, AFinal],
                kind: FVar(macro :Array<Int>, {
                    expr: EArrayDecl(entries),
                    pos: Context.currentPos()
                }),
                pos: Context.currentPos(),
            }
        ]);
    }

    /** The merged table, gated by conformance and cached by input hash. */
    public static function table():Array<Int> {
        load();
        return cachedTable;
    }

    /** The Unicode release the table was built from. */
    public static function version():String {
        load();
        return cachedVersion;
    }

    // ------------------------------------------------------------------
    // Pipeline
    // ------------------------------------------------------------------

    static function load():Void {
        if (cachedTable != null) {
            return;
        }
        final fetchVersion = Context.definedValue("fetch-unicode");
        final version = fetchVersion != null ? fetchVersion : PINNED_VERSION;
        if (fetchVersion != null) {
            fetchFiles(fetchVersion);
        }

        final contents = [for (name in SOURCE_FILES) readDataFile(name + "-" + version + ".txt")];
        final digest = Md5.encode([for (c in contents) Md5.encode(c)].join(""));

        if (loadCache(digest)) {
            return;
        }

        final table = mergeTable(parsePropertyFile(contents[0]), parsePropertyFile(contents[1]), parseIncbSections(contents[2]));
        runConformance(table, contents[3]);
        saveCache(digest, version, table);
        cachedTable = table;
        cachedVersion = version;
    }

    static function dataDir():String {
        return "tools/unicode-data";
    }

    static function readDataFile(fileName:String):String {
        final path = dataDir() + "/" + fileName;
        if (!sys.FileSystem.exists(path)) {
            Context.fatalError("pinned Unicode data file is missing: "
                + path
                + " (expected next to the compilation root; run from the repository root, or refresh with -D fetch-unicode=<version>)",
                Context.currentPos());
        }
        return sys.io.File.getContent(path);
    }

    /**
        Downloads the four files of one Unicode release with curl. The
        chunked-transfer decoder of `sys.Http` in Haxe 4.3.7 discards
        misaligned bytes when TCP segmentation splits a chunk header, so
        `haxe.Http` corrupts these files nondeterministically; the
        conformance gate rejects the corrupt downloads, and curl reads
        the same URLs correctly. The subprocess stays inside this macro
        pipeline: no script outside the compilation participates.
    **/
    static function fetchFiles(version:String):Void {
        final urls:Array<{name:String, url:String}> = [
            {name: "GraphemeBreakProperty", url: "https://unicode.org/Public/" + version + "/ucd/auxiliary/GraphemeBreakProperty.txt"},
            {name: "emoji-data", url: "https://unicode.org/Public/" + version + "/ucd/emoji/emoji-data.txt"},
            {name: "DerivedCoreProperties", url: "https://unicode.org/Public/" + version + "/ucd/DerivedCoreProperties.txt"},
            {name: "GraphemeBreakTest", url: "https://unicode.org/Public/" + version + "/ucd/auxiliary/GraphemeBreakTest.txt"},
        ];
        for (entry in urls) {
            final proc = new sys.io.Process("curl", ["-fsSL", entry.url]);
            // Drain stdout to EOF before waiting: the largest file
            // exceeds the pipe buffer, and waiting first deadlocks.
            final output = proc.stdout.readAll().toString();
            final code = proc.exitCode();
            proc.close();
            if (code != 0 || output.length == 0) {
                Context.fatalError("download failed for " + entry.name + " " + version + " (curl exit " + code + "): " + entry.url, Context.currentPos());
            }
            sys.io.File.saveContent(dataDir() + "/" + entry.name + "-" + version + ".txt", output);
        }
    }

    // ------------------------------------------------------------------
    // Cache
    // ------------------------------------------------------------------

    static function cachePath(digest:String):String {
        return "out/unicode-cache/grapheme-" + digest + ".txt";
    }

    static function loadCache(digest:String):Bool {
        final path = cachePath(digest);
        if (!sys.FileSystem.exists(path)) {
            return false;
        }
        final lines = sys.io.File.getContent(path).split("\n");
        if (lines.length < 2) {
            return false;
        }
        cachedVersion = StringTools.trim(lines[0]);
        cachedTable = [
            for (part in lines[1].split(",")) if (StringTools.trim(part).length > 0) Std.parseInt(StringTools.trim(part))
        ];
        for (v in cachedTable) {
            if (v == null) {
                Context.fatalError("corrupt unicode cache entry: " + path, Context.currentPos());
            }
        }
        return true;
    }

    static function saveCache(digest:String, version:String, table:Array<Int>):Void {
        final path = cachePath(digest);
        final dir = haxe.io.Path.directory(path);
        if (!sys.FileSystem.exists(dir)) {
            sys.FileSystem.createDirectory(dir);
        }
        sys.io.File.saveContent(path, version + "\n" + table.join(",") + "\n");
    }

    // ------------------------------------------------------------------
    // Parsing
    // ------------------------------------------------------------------

    /** Parses `00A9..00AE ; Property # comment` lines from a UCD property file. */
    static function parsePropertyFile(text:String):Array<PropertyRange> {
        final ranges:Array<PropertyRange> = [];
        for (rawLine in text.split("\n")) {
            final line = stripComment(rawLine);
            if (line.length == 0) {
                continue;
            }
            final parts = line.split(";");
            if (parts.length < 2) {
                continue;
            }
            final bounds = StringTools.trim(parts[0]).split("..");
            final start = parseHex(bounds[0]);
            final end = bounds.length > 1 ? parseHex(bounds[1]) : start;
            if (start == null || end == null) {
                continue;
            }
            ranges.push({start: start, end: end, property: StringTools.trim(parts[1])});
        }
        return ranges;
    }

    /** UCD code point bounds are hexadecimal. */
    static function parseHex(text:String):Null<Int> {
        final trimmed = StringTools.trim(text);
        if (trimmed.length == 0) {
            return null;
        }
        return Std.parseInt("0x" + trimmed);
    }

    /**
        Parses the Indic_Conjunct_Break sections of
        DerivedCoreProperties.txt. Lines carry `; InCB; Value`, so the
        property arrives in two fields; the section header supplies the
        active property name. Any semicolon line that does not match the
        section shape ends the section.
    **/
    static function parseIncbSections(text:String):Array<PropertyRange> {
        final ranges:Array<PropertyRange> = [];
        var current:Null<String> = null;
        for (rawLine in text.split("\n")) {
            final trimmed = StringTools.trim(rawLine);
            final headerMarker = "# Indic_Conjunct_Break=";
            if (StringTools.startsWith(trimmed, headerMarker)) {
                current = trimmed.substr(headerMarker.length);
                continue;
            }
            if (current == null) {
                continue;
            }
            final line = stripComment(rawLine);
            if (line.length == 0) {
                continue;
            }
            final parts = line.split(";");
            if (parts.length >= 3) {
                final bounds = StringTools.trim(parts[0]).split("..");
                final start = parseHex(bounds[0]);
                final end = bounds.length > 1 ? parseHex(bounds[1]) : start;
                final marker = StringTools.trim(parts[1]);
                final value = StringTools.trim(parts[2]);
                if (marker == "InCB" && value == current && start != null && end != null) {
                    ranges.push({start: start, end: end, property: value});
                    continue;
                }
            }
            current = null;
        }
        return ranges;
    }

    static function stripComment(line:String):String {
        final hash = line.indexOf("#");
        return StringTools.trim(hash < 0 ? line : line.substr(0, hash));
    }

    // ------------------------------------------------------------------
    // Merge
    // ------------------------------------------------------------------

    /** Grapheme_Cluster_Break class values for field 0 of the packed word. */
    static function gcbValue(property:String):Null<Int> {
        return switch (property) {
            case "CR": 1;
            case "LF": 2;
            case "Control": 3;
            case "Extend": 4;
            case "ZWJ": 5;
            case "Regional_Indicator": 6;
            case "Prepend": 7;
            case "SpacingMark": 8;
            case "L": 9;
            case "V": 10;
            case "T": 11;
            case "LV": 12;
            case "LVT": 13;
            default: null;
        };
    }

    /** Indic_Conjunct_Break values for bits 5-6 of the packed word. */
    static function incbValue(property:String):Null<Int> {
        return switch (property) {
            case "Consonant": 32;
            case "Linker": 64;
            case "Extend": 96;
            default: null;
        };
    }

    /**
        Merges the three property files into disjoint ranges. Field slots:
        0 Grapheme_Cluster_Break class, 1 Extended_Pictographic,
        2 Indic_Conjunct_Break. Ranges within one field never overlap, so
        the sweep keeps one active value per field and ORs the slots
        together. The property files group ranges by property and code
        point. A range end and an adjacent range start of the same field
        can arrive in either order; clearing before setting at a shared
        position keeps the active value correct.
    **/
    static function mergeTable(gcb:Array<PropertyRange>, emoji:Array<PropertyRange>, incb:Array<PropertyRange>):Array<Int> {
        final events:Array<FieldEvent> = [];
        final gcbRanges:Array<PropertyRange> = [];
        for (range in emoji) {
            if (range.property == "Extended_Pictographic") {
                gcbRanges.push(range);
            }
        }
        for (range in gcb) {
            final value = gcbValue(range.property);
            if (value == null) {
                Context.fatalError("unknown Grapheme_Cluster_Break property: " + range.property, Context.currentPos());
            }
            events.push({pos: range.start, field: 0, value: value});
            events.push({pos: range.end + 1, field: 0, value: 0});
        }
        for (range in gcbRanges) {
            events.push({pos: range.start, field: 1, value: 16});
            events.push({pos: range.end + 1, field: 1, value: 0});
        }
        for (range in incb) {
            final value = incbValue(range.property);
            if (value == null) {
                Context.fatalError("unknown Indic_Conjunct_Break property: " + range.property, Context.currentPos());
            }
            events.push({pos: range.start, field: 2, value: value});
            events.push({pos: range.end + 1, field: 2, value: 0});
        }
        events.sort(compareEvents);

        final table:Array<Int> = [];
        final active = [0, 0, 0];
        var pos = 0;
        var index = 0;
        while (index < events.length) {
            final next = events[index].pos;
            if (next > pos) {
                final packed = active[0] | active[1] | active[2];
                if (packed != 0) {
                    table.push(pos);
                    table.push(next - 1);
                    table.push(packed);
                }
                pos = next;
            }
            while (index < events.length && events[index].pos == pos) {
                final event = events[index];
                active[event.field] = event.value;
                index += 1;
            }
        }
        // The last event position is the end of the highest listed range
        // plus one; everything above it stays class Other.
        if (pos > 0x110000) {
            Context.fatalError("grapheme table sweep ended past U+10FFFF (U+" + StringTools.hex(pos) + ")", Context.currentPos());
        }
        var prevEnd = -1;
        for (i in 0...Std.int(table.length / 3)) {
            final start = table[i * 3];
            if (start <= prevEnd) {
                Context.fatalError("overlapping grapheme table ranges at U+" + StringTools.hex(start), Context.currentPos());
            }
            prevEnd = table[i * 3 + 1];
        }
        return table;
    }

    static function compareEvents(a:FieldEvent, b:FieldEvent):Int {
        if (a.pos != b.pos) {
            return a.pos < b.pos ? -1 : 1;
        }
        final aClear = a.value == 0 ? 0 : 1;
        final bClear = b.value == 0 ? 0 : 1;
        return aClear - bClear;
    }

    // ------------------------------------------------------------------
    // Conformance
    // ------------------------------------------------------------------

    /**
        Runs the official GraphemeBreakTest vectors through the shared
        walk. Each line lists code points with the expected boundary mark
        before every one of them. One failure aborts the compilation.
    **/
    static function runConformance(table:Array<Int>, testText:String):Void {
        var failures = 0;
        var firstFailure:Null<String> = null;
        for (rawLine in testText.split("\n")) {
            final body = stripComment(rawLine);
            if (body.length == 0) {
                continue;
            }
            final codes:Array<Int> = [];
            final expected:Array<Bool> = [];
            var malformed = false;
            for (token in body.split(" ")) {
                if (token.length == 0) {
                    continue;
                }
                if (token == "÷") {
                    expected.push(true);
                } else if (token == "×") {
                    expected.push(false);
                } else {
                    final code = Std.parseInt("0x" + token);
                    if (code == null) {
                        malformed = true;
                        break;
                    }
                    codes.push(code);
                }
            }
            // The line starts with a mark before the first code point and
            // ends with the end-of-text mark (GB2), so marks outnumber
            // codes by one.
            if (malformed || codes.length == 0 || expected.length != codes.length + 1) {
                Context.fatalError("malformed GraphemeBreakTest line: " + rawLine, Context.currentPos());
            }
            expected.pop();
            final actual = GraphemeWalk.boundaryFlags(table, codes);
            for (i in 0...codes.length) {
                if (actual[i] != expected[i]) {
                    failures += 1;
                    if (firstFailure == null) {
                        firstFailure = "line " + StringTools.trim(rawLine) + ": boundary before U+" + StringTools.hex(codes[i]).toUpperCase() + " expected "
                            + expected[i] + " got " + actual[i];
                    }
                    break;
                }
            }
        }
        if (failures > 0) {
            Context.fatalError("grapheme walk failed " + failures + " GraphemeBreakTest lines; first: " + firstFailure, Context.currentPos());
        }
    }
}
#end
