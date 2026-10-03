#if (macro || reflaxe_runtime)
package;

/**
    Per-file compact emission-origin mapping.

    Header fields (revision, haxe version, defines) identify the
    generator; a missing or empty field causes the consumer to
    reject the mapping as Unmapped.

    The lines array is indexed by 0-based line number. A null
    entry means no mapping for that line. The columns map holds
    sparse column-level overrides keyed by line index.

    Format v2 adds a global callStackFrames table and, on every line
    with a Haxe source, the 1-based source line/column and the list of
    call-stack frame ids. Format v3 adds a per-line origin marker ("exact"
    vs "inherited") so backfilled no-event lines cannot masquerade as
    emission-event matches. Format v1 (without those fields) still reads
    back into the same structure with empty call stacks and 0 line/col.
**/
class EmitOriginMap {
    public final filePath:String;
    public final revision:String;
    public final haxeVersion:String;
    public final defines:Map<String, String>;
    public final sourceFiles:Array<String>;
    public final frames:Array<String>;
    public final callStackFrames:Array<StackFrame>;
    public final lines:Array<Null<EmitLineMapping>>;
    public final columns:Map<Int, Array<EmitColumnSegment>>;

    public function new(filePath:String, revision:String, haxeVersion:String,
            defines:Map<String, String>, sourceFiles:Array<String>, frames:Array<String>,
            callStackFrames:Array<StackFrame>, lines:Array<Null<EmitLineMapping>>,
            columns:Map<Int, Array<EmitColumnSegment>>) {
        this.filePath = filePath;
        this.revision = revision;
        this.haxeVersion = haxeVersion;
        this.defines = defines;
        this.sourceFiles = sourceFiles;
        this.frames = frames;
        this.callStackFrames = callStackFrames;
        this.lines = lines;
        this.columns = columns;
    }

    /**
        Serializes this mapping to compact JSON. Writes v3 when the line
        table carries any inherited entry, v2 when it carries any call
        stack beyond the v1 span, otherwise v1. v3 is the current writer
        default.
    **/
    public function write():String {
        final defsObj:Dynamic = {};
        for (key in defines.keys())
            Reflect.setField(defsObj, key, defines.get(key));

        final hasCallStacks = callStackFrames.length > 0 || linesContainDetail();
        final hasInherited = linesContainInherited();
        final version:Int = hasInherited ? 3 : (hasCallStacks ? 2 : 1);

        final serializedLines:Array<Dynamic> = [];
        for (entry in lines) {
            if (entry == null) {
                serializedLines.push(null);
            } else if (entry.sourceFileId < 0) {
                serializedLines.push([entry.frameId]);
            } else if (version >= 3) {
                serializedLines.push([entry.frameId, entry.sourceFileId,
                    entry.sourceStart, entry.sourceEnd, entry.sourceLine,
                    entry.sourceColumn, entry.callStack, entry.origin]);
            } else if (version >= 2) {
                serializedLines.push([entry.frameId, entry.sourceFileId,
                    entry.sourceStart, entry.sourceEnd, entry.sourceLine,
                    entry.sourceColumn, entry.callStack]);
            } else {
                serializedLines.push([entry.frameId, entry.sourceFileId, entry.sourceStart, entry.sourceEnd]);
            }
        }

        final serializedColumns:Array<Dynamic> = [];
        for (lineIndex in columns.keys()) {
            final segments = columns.get(lineIndex);
            final segList:Array<Dynamic> = [];
            for (seg in segments) {
                if (seg.mapping == null) {
                    segList.push([seg.startCol, seg.endCol, null]);
                } else if (seg.mapping.sourceFileId < 0) {
                    segList.push([seg.startCol, seg.endCol, seg.mapping.frameId]);
                } else {
                    segList.push([seg.startCol, seg.endCol, seg.mapping.frameId,
                        seg.mapping.sourceFileId, seg.mapping.sourceStart, seg.mapping.sourceEnd]);
                }
            }
            serializedColumns.push([lineIndex, segList]);
        }

        final serializedFrames:Array<Dynamic> = [];
        for (frame in callStackFrames) {
            serializedFrames.push({name: frame.name, file: frame.file, line: frame.line, column: frame.column});
        }

        final payload:Dynamic = {
            v: version,
            revision: revision,
            haxeVersion: haxeVersion,
            defines: defsObj,
            sourceFiles: sourceFiles,
            frames: frames,
            lines: serializedLines,
            cols: serializedColumns
        };
        if (version >= 2)
            Reflect.setField(payload, "callStackFrames", serializedFrames);

        return haxe.Json.stringify(payload, null, "\t") + "\n";
    }

    function linesContainDetail():Bool {
        for (entry in lines) {
            if (entry != null && entry.sourceFileId >= 0
                && (entry.sourceLine != 0 || entry.sourceColumn != 0 || entry.callStack.length > 0))
                return true;
        }
        return false;
    }

    function linesContainInherited():Bool {
        for (entry in lines) {
            if (entry != null && entry.origin == "inherited")
                return true;
        }
        return false;
    }

    /**
        Deserializes a JSON compact mapping produced by write().
        Returns null when the JSON is structurally invalid or missing
        required fields. Reads both v1 and v2.
    **/
    public static function read(json:String):Null<EmitOriginMap> {
        final data:Dynamic = try { haxe.Json.parse(json); } catch (_:Dynamic) { return null; };
        if (data == null || !Std.isOfType(Reflect.field(data, "v"), Int))
            return null;
        final version:Int = Reflect.field(data, "v");
        if (version != 1 && version != 2 && version != 3)
            return null;
        final revision:Null<String> = Reflect.field(data, "revision");
        final haxeVersion:Null<String> = Reflect.field(data, "haxeVersion");
        final definesRaw:Null<Dynamic> = Reflect.field(data, "defines");
        final sourceFilesRaw:Null<Dynamic> = Reflect.field(data, "sourceFiles");
        final framesRaw:Null<Dynamic> = Reflect.field(data, "frames");
        final linesRaw:Null<Dynamic> = Reflect.field(data, "lines");
        final colsRaw:Null<Dynamic> = Reflect.field(data, "cols");
        if (revision == null || haxeVersion == null || definesRaw == null
            || sourceFilesRaw == null || framesRaw == null || linesRaw == null)
            return null;
        if (!Std.isOfType(revision, String) || !Std.isOfType(haxeVersion, String)
            || !Std.isOfType(sourceFilesRaw, Array) || !Std.isOfType(framesRaw, Array)
            || !Std.isOfType(linesRaw, Array) || !Std.isOfType(colsRaw, Array))
            return null;

        final defines:Map<String, String> = new Map();
        for (f in Reflect.fields(definesRaw))
            defines.set(f, Std.string(Reflect.field(definesRaw, f)));

        final sourceFiles = readStringArray(sourceFilesRaw);
        final frames = readStringArray(framesRaw);
        final callStackFrames = readCallStackFrames(Reflect.field(data, "callStackFrames"));
        final lines = readLineMappings(linesRaw);
        final columns = readColumnTable(colsRaw);
        if (sourceFiles == null || frames == null || lines == null || columns == null)
            return null;
        return new EmitOriginMap("", revision, haxeVersion, defines, sourceFiles, frames,
            callStackFrames, lines, columns);
    }

    static function readStringArray(raw:Dynamic):Null<Array<String>> {
        if (!Std.isOfType(raw, Array))
            return null;
        final arr:Array<Dynamic> = cast raw;
        final out:Array<String> = [];
        for (entry in arr)
            out.push(Std.string(entry));
        return out;
    }

    static function readCallStackFrames(raw:Dynamic):Array<StackFrame> {
        if (!Std.isOfType(raw, Array))
            return [];
        final arr:Array<Dynamic> = cast raw;
        final out:Array<StackFrame> = [];
        for (entry in arr) {
            if (entry == null || !Reflect.isObject(entry))
                continue;
            out.push({
                name: Std.string(Reflect.field(entry, "name")),
                file: Std.string(Reflect.field(entry, "file")),
                line: Reflect.field(entry, "line") == null ? 0 : cast Reflect.field(entry, "line"),
                column: Reflect.field(entry, "column") == null ? 0 : cast Reflect.field(entry, "column")
            });
        }
        return out;
    }

    static function readLineMappings(raw:Dynamic):Null<Array<Null<EmitLineMapping>>> {
        if (!Std.isOfType(raw, Array))
            return null;
        final arr:Array<Dynamic> = cast raw;
        final out:Array<Null<EmitLineMapping>> = [];
        for (entry in arr) {
            if (entry == null) {
                out.push(null);
                continue;
            }
            if (Reflect.isObject(entry) && !Std.isOfType(entry, Array)) {
                // v3 null-with-reason: {u: "reason"}
                // Preserved as null (reason stored externally); read ignores it.
                out.push(null);
                continue;
            }
            if (!Std.isOfType(entry, Array))
                return null;
            final tuple:Array<Dynamic> = cast entry;
            if (tuple.length < 1)
                return null;
            final frameId:Int = cast tuple[0];
            if (tuple.length >= 8) {
                // v3: frame, sourceFile, start, end, line, column, callStack[], origin
                final csRaw:Dynamic = tuple[6];
                final cs:Array<Int> = Std.isOfType(csRaw, Array) ? cast csRaw : [];
                final origin:String = cast tuple[7];
                out.push({
                    frameId: frameId,
                    sourceFileId: cast tuple[1],
                    sourceStart: cast tuple[2],
                    sourceEnd: cast tuple[3],
                    sourceLine: cast tuple[4],
                    sourceColumn: cast tuple[5],
                    callStack: cs,
                    origin: origin
                });
            } else if (tuple.length >= 7) {
                // v2: frame, sourceFile, start, end, line, column, callStack[]
                final csRaw:Dynamic = tuple[6];
                final cs:Array<Int> = Std.isOfType(csRaw, Array) ? cast csRaw : [];
                out.push({
                    frameId: frameId,
                    sourceFileId: cast tuple[1],
                    sourceStart: cast tuple[2],
                    sourceEnd: cast tuple[3],
                    sourceLine: cast tuple[4],
                    sourceColumn: cast tuple[5],
                    callStack: cs,
                    origin: "exact"
                });
            } else if (tuple.length >= 4) {
                // v1: frame, sourceFile, start, end
                out.push({
                    frameId: frameId,
                    sourceFileId: cast tuple[1],
                    sourceStart: cast tuple[2],
                    sourceEnd: cast tuple[3],
                    sourceLine: 0,
                    sourceColumn: 0,
                    callStack: [],
                    origin: "exact"
                });
            } else {
                out.push({
                    frameId: frameId,
                    sourceFileId: -1,
                    sourceStart: 0,
                    sourceEnd: 0,
                    sourceLine: 0,
                    sourceColumn: 0,
                    callStack: [],
                    origin: "exact"
                });
            }
        }
        return out;
    }

    static function readColumnTable(raw:Dynamic):Null<Map<Int, Array<EmitColumnSegment>>> {
        if (raw == null)
            return new Map();
        if (!Std.isOfType(raw, Array))
            return new Map();
        final arr:Array<Dynamic> = cast raw;
        final out:Map<Int, Array<EmitColumnSegment>> = new Map();
        for (entry in arr) {
            if (!Std.isOfType(entry, Array) || entry.length < 2)
                return null;
            final pair:Array<Dynamic> = cast entry;
            final lineIndex:Int = cast pair[0];
            final segsRaw:Dynamic = pair[1];
            if (!Std.isOfType(segsRaw, Array))
                return null;
            final segsArr:Array<Dynamic> = cast segsRaw;
            final segs:Array<EmitColumnSegment> = [];
            for (segRaw in segsArr) {
                if (!Std.isOfType(segRaw, Array))
                    return null;
                final seg:Array<Dynamic> = cast segRaw;
                if (seg.length < 3)
                    return null;
                final startCol:Int = cast seg[0];
                final endCol:Int = cast seg[1];
                final mapRaw = seg[2];
                if (mapRaw == null) {
                    segs.push({startCol: startCol, endCol: endCol, mapping: null});
                } else if (Std.isOfType(mapRaw, Array)) {
                    final mapArr:Array<Dynamic> = cast mapRaw;
                    if (mapArr.length >= 4) {
                        segs.push({
                            startCol: startCol, endCol: endCol,
                            mapping: {
                                frameId: cast mapArr[0],
                                sourceFileId: cast mapArr[1],
                                sourceStart: cast mapArr[2],
                                sourceEnd: cast mapArr[3],
                                sourceLine: 0,
                                sourceColumn: 0,
                                callStack: [],
                                origin: "exact"
                            }
                        });
                    } else if (mapArr.length >= 1) {
                        segs.push({
                            startCol: startCol, endCol: endCol,
                            mapping: {
                                frameId: cast mapArr[0],
                                sourceFileId: -1,
                                sourceStart: 0,
                                sourceEnd: 0,
                                sourceLine: 0,
                                sourceColumn: 0,
                                callStack: [],
                                origin: "exact"
                            }
                        });
                    } else {
                        return null;
                    }
                } else {
                    final frameId:Int = cast mapRaw;
                    segs.push({
                        startCol: startCol, endCol: endCol,
                        mapping: {
                            frameId: frameId,
                            sourceFileId: -1,
                            sourceStart: 0,
                            sourceEnd: 0,
                            sourceLine: 0,
                            sourceColumn: 0,
                            callStack: [],
                            origin: "exact"
                        }
                    });
                }
            }
            out.set(lineIndex, segs);
        }
        return out;
    }

    /**
        Resolves a generated (line, column) position to its emitter
        branch and Haxe source position.

        The consumer validates every access path: line / column bounds,
        internal pointer validity, and header presence. Any failure
        returns Unmapped with the reason.
    **/
    public function resolve(line:Int, column:Int):EmitResolution {
        if (revision == null || revision == "" || revision == "unknown")
            return EmitResolution.unmapped("Missing generator revision");
        if (haxeVersion == null || haxeVersion == "")
            return EmitResolution.unmapped("Missing Haxe version");
        if (defines == null)
            return EmitResolution.unmapped("Missing defines");

        if (line < 1 || line > lines.length)
            return EmitResolution.unmapped("Line " + line + " out of bounds (max " + lines.length + ")");
        if (column < 1)
            return EmitResolution.unmapped("Column " + column + " out of bounds");

        final lineIndex = line - 1;

        final colSegments = columns.get(lineIndex);
        if (colSegments != null) {
            for (seg in colSegments) {
                if (column >= seg.startCol && column < seg.endCol) {
                    if (seg.mapping == null)
                        return EmitResolution.unmapped("Column " + column + " explicitly unmapped");
                    return resolveFromMapping(seg.mapping);
                }
            }
        }

        final entry = lines[lineIndex];
        if (entry == null)
            return EmitResolution.unmapped("No mapping for line " + line);
        return resolveFromMapping(entry);
    }

    function resolveFromMapping(mapping:EmitLineMapping):EmitResolution {
        final frame = mapping.frameId >= 0 && mapping.frameId < frames.length
            ? frames[mapping.frameId] : null;
        if (frame == null)
            return EmitResolution.unmapped("Invalid frame id " + mapping.frameId);
        if (mapping.sourceFileId < 0)
            return EmitResolution.mapped(frame, null, 0, 0);
        if (mapping.sourceFileId >= sourceFiles.length)
            return EmitResolution.unmapped("Invalid source file id " + mapping.sourceFileId);
        final sourceFile = sourceFiles[mapping.sourceFileId];
        if (mapping.sourceStart < 0 || mapping.sourceEnd <= mapping.sourceStart)
            return EmitResolution.unmapped("Invalid source span " + mapping.sourceStart + "-" + mapping.sourceEnd);
        if (!sys.FileSystem.exists(sourceFile))
            return EmitResolution.unmapped("Source file not found: " + sourceFile);
        final fileBytes = sys.io.File.getContent(sourceFile);
        if (mapping.sourceEnd > fileBytes.length)
            return EmitResolution.unmapped("Source span exceeds file length");
        return EmitResolution.mapped(frame, sourceFile, mapping.sourceStart, mapping.sourceEnd);
    }

    /**
        Renders a one-command trace for a generated (line, column): the
        emitter frame (branch), the Haxe source file:line:column, and the
        generation-time call stack from innermost to outermost.
    **/
    public function traceLine(line:Int, column:Int):String {
        if (line < 1 || line > lines.length)
            return "Unmapped: line " + line + " out of bounds (max " + lines.length + ")";
        final entry = lines[line - 1];
        if (entry == null)
            return "Unmapped: no mapping for line " + line;
        final frame = entry.frameId >= 0 && entry.frameId < frames.length
            ? frames[entry.frameId] : "<unknown frame>";
        final sb = new StringBuf();
        sb.add("line " + line + " (col " + column + ") [" + entry.origin + "] -> frame=" + frame);
        if (entry.sourceFileId >= 0 && entry.sourceFileId < sourceFiles.length) {
            sb.add("\n  Haxe source: " + sourceFiles[entry.sourceFileId]
                + ":" + entry.sourceLine + ":" + entry.sourceColumn
                + " (bytes " + entry.sourceStart + "-" + entry.sourceEnd + ")");
        } else {
            sb.add("\n  Haxe source: <none recorded>");
        }
        sb.add("\n  Call stack (" + entry.callStack.length + " frames, innermost first):");
        if (entry.callStack.length == 0) {
            sb.add("\n    <no call stack recorded>");
        } else {
            var depth = 0;
            for (fid in entry.callStack) {
                if (depth >= 16) {
                    sb.add("\n    ... (" + (entry.callStack.length - depth) + " more)");
                    break;
                }
                if (fid >= 0 && fid < callStackFrames.length) {
                    final fr = callStackFrames[fid];
                    final loc = fr.file != "" ? fr.file + ":" + fr.line + ":" + fr.column : "<n/a>";
                    sb.add("\n    #" + depth + " " + fr.name + "  at " + loc);
                } else {
                    sb.add("\n    #" + depth + " <invalid frame id " + fid + ">");
                }
                depth++;
            }
        }
        return sb.toString();
    }
}

/** Per-line compact mapping entry. */
typedef EmitLineMapping = {
    final frameId:Int;
    final sourceFileId:Int;
    final sourceStart:Int;
    final sourceEnd:Int;
    final sourceLine:Int;
    final sourceColumn:Int;
    final callStack:Array<Int>;
    /** "exact" for event-matched, "inherited" for backfilled. */
    final origin:String;
};

/** Column-range segment within one generated line. */
typedef EmitColumnSegment = {
    final startCol:Int;
    final endCol:Int;
    final mapping:Null<EmitLineMapping>;
};

/** One generation-time call-stack frame, resolved to a name plus source position. */
typedef StackFrame = {
    final name:String;
    final file:String;
    final line:Int;
    final column:Int;
};

/**
    Resolution result from EmitOriginMap.resolve().

    Mapped: emission frame (branch name) and source position (file + span).
    Unmapped: reason why no mapping could be produced.
**/
class EmitResolution {
    public final frame:Null<String>;
    public final sourceFile:Null<String>;
    public final sourceStart:Int;
    public final sourceEnd:Int;
    public final reason:Null<String>;

    function new(frame:Null<String>, sourceFile:Null<String>, sourceStart:Int, sourceEnd:Int, reason:Null<String>) {
        this.frame = frame;
        this.sourceFile = sourceFile;
        this.sourceStart = sourceStart;
        this.sourceEnd = sourceEnd;
        this.reason = reason;
    }

    public function isMapped():Bool {
        return frame != null;
    }

    public static function mapped(frame:String, sourceFile:Null<String>, sourceStart:Int, sourceEnd:Int):EmitResolution {
        return new EmitResolution(frame, sourceFile, sourceStart, sourceEnd, null);
    }

    public static function unmapped(reason:String):EmitResolution {
        return new EmitResolution(null, null, 0, 0, reason);
    }

    public function toString():String {
        if (isMapped())
            return "Mapped(frame=" + frame + ", source=" + sourceFile + ":" + sourceStart + "-" + sourceEnd + ")";
        return "Unmapped(" + reason + ")";
    }
}

#end
