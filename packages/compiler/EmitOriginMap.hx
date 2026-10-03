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
**/
class EmitOriginMap {
    public final filePath:String;
    public final revision:String;
    public final haxeVersion:String;
    public final defines:Map<String, String>;
    public final sourceFiles:Array<String>;
    public final frames:Array<String>;
    public final lines:Array<Null<EmitLineMapping>>;
    public final columns:Map<Int, Array<EmitColumnSegment>>;

    public function new(filePath:String, revision:String, haxeVersion:String,
            defines:Map<String, String>, sourceFiles:Array<String>, frames:Array<String>,
            lines:Array<Null<EmitLineMapping>>, columns:Map<Int, Array<EmitColumnSegment>>) {
        this.filePath = filePath;
        this.revision = revision;
        this.haxeVersion = haxeVersion;
        this.defines = defines;
        this.sourceFiles = sourceFiles;
        this.frames = frames;
        this.lines = lines;
        this.columns = columns;
    }

    /**
        Serializes this mapping to compact JSON matching the v1 format.
    **/
    public function write():String {
        final defsObj:Dynamic = {};
        for (key in defines.keys())
            Reflect.setField(defsObj, key, defines.get(key));

        final serializedLines:Array<Dynamic> = [];
        for (entry in lines) {
            if (entry == null) {
                serializedLines.push(null);
            } else if (entry.sourceFileId < 0) {
                serializedLines.push([entry.frameId]);
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

        final payload:Dynamic = {
            v: 1,
            revision: revision,
            haxeVersion: haxeVersion,
            defines: defsObj,
            sourceFiles: sourceFiles,
            frames: frames,
            lines: serializedLines,
            cols: serializedColumns
        };
        return haxe.Json.stringify(payload, null, "\t") + "\n";
    }

    /**
        Deserializes a JSON compact mapping produced by write().
        Returns null when the JSON is structurally invalid or missing
        required fields.
    **/
    public static function read(json:String):Null<EmitOriginMap> {
        final data:Dynamic = try { haxe.Json.parse(json); } catch (_:Dynamic) { return null; };
        if (data == null || !Std.isOfType(Reflect.field(data, "v"), Int))
            return null;
        if (Reflect.field(data, "v") != 1)
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
        final lines = readLineMappings(linesRaw);
        final columns = readColumnTable(colsRaw);
        if (sourceFiles == null || frames == null || lines == null || columns == null)
            return null;
        return new EmitOriginMap("", revision, haxeVersion, defines, sourceFiles, frames, lines, columns);
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
            if (!Std.isOfType(entry, Array))
                return null;
            final tuple:Array<Dynamic> = cast entry;
            if (tuple.length < 1)
                return null;
            final frameId:Int = cast tuple[0];
            if (tuple.length >= 4) {
                out.push({
                    frameId: frameId,
                    sourceFileId: cast tuple[1],
                    sourceStart: cast tuple[2],
                    sourceEnd: cast tuple[3]
                });
            } else {
                out.push({
                    frameId: frameId,
                    sourceFileId: -1,
                    sourceStart: 0,
                    sourceEnd: 0
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
                                sourceEnd: cast mapArr[3]
                            }
                        });
                    } else if (mapArr.length >= 1) {
                        segs.push({
                            startCol: startCol, endCol: endCol,
                            mapping: {
                                frameId: cast mapArr[0],
                                sourceFileId: -1,
                                sourceStart: 0,
                                sourceEnd: 0
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
                            sourceEnd: 0
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
}

/** Per-line compact mapping entry. */
typedef EmitLineMapping = {
    final frameId:Int;
    final sourceFileId:Int;
    final sourceStart:Int;
    final sourceEnd:Int;
};

/** Column-range segment within one generated line. */
typedef EmitColumnSegment = {
    final startCol:Int;
    final endCol:Int;
    final mapping:Null<EmitLineMapping>;
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
