#if (macro || reflaxe_runtime)
package;

import haxe.macro.Context;
import haxe.macro.Expr.Position;
import EmitOriginMap.EmitLineMapping;
import EmitOriginMap;
import EmitOriginMap.EmitResolution;
import EmitOriginMap.StackFrame;

/**
    Emission-origin recording sink.

    Records the emitter branch and Haxe source position at each
    emission "push" so one generation pass can resolve every
    host-compiler diagnostic back to the emitting branch and the
    Haxe source node that produced it.

    The sink interns source file paths, branch names, and call-stack
    frames to integer ids, accumulates events during generation, and
    produces per-file compact EmitOriginMap instances at finalization
    time.

    Each event now also captures the generation-time call stack
    (haxe.CallStack.callStack()) parsed into structured StackFrame
    records, plus the 1-based source line and column derived from the
    recorded Haxe Position. The call stack is what lets one generated
    line be traced back through every emitting function to the Haxe
    source, not just to the nearest handwritten tag.
**/
class EmitSink {
    public static var enabled(default, null):Bool = false;

    static var events:Array<EmitEvent> = [];
    static var sourcePathIds:Map<String, Int> = new Map();
    static var sourcePaths:Array<String> = [];
    static var frameIds:Map<String, Int> = new Map();
    static var frames:Array<String> = [];
    static var callStackFrameIds:Map<String, Int> = new Map();
    static var callStackFrames:Array<StackFrame> = [];
    static var capturedRevision:Null<String> = null;
    static var capturedHaxeVersion:Null<String> = null;
    static var capturedDefines:Null<Map<String, String>> = null;

    public static function activate():Void {
        if (enabled)
            return;
        enabled = true;
        events.resize(0);
        sourcePathIds = new Map();
        sourcePaths.resize(0);
        frameIds = new Map();
        frames.resize(0);
        callStackFrameIds = new Map();
        callStackFrames.resize(0);
        capturedRevision = null;
        capturedHaxeVersion = null;
        capturedDefines = null;
    }

    public static function internSourceFile(path:String):Int {
        final existing = sourcePathIds.get(path);
        if (existing != null)
            return existing;
        final id = sourcePaths.length;
        sourcePathIds.set(path, id);
        sourcePaths.push(path);
        return id;
    }

    public static function internFrame(name:String):Int {
        final existing = frameIds.get(name);
        if (existing != null)
            return existing;
        final id = frames.length;
        frameIds.set(name, id);
        frames.push(name);
        return id;
    }

    static function internCallStackFrame(frame:StackFrame):Int {
        final key = frame.name + "|" + frame.file + ":" + frame.line + ":" + frame.column;
        final existing = callStackFrameIds.get(key);
        if (existing != null)
            return existing;
        final id = callStackFrames.length;
        callStackFrameIds.set(key, id);
        callStackFrames.push(frame);
        return id;
    }

    public static function record(branch:Null<String>, pos:Null<Position>, text:Null<String>):Void {
        if (!enabled || branch == null || text == null)
            return;
        var sourceFile:Null<String> = null;
        var sourceLine = 0;
        var sourceColumn = 0;
        if (pos != null) {
            try {
                final info = Context.getPosInfos(pos);
                sourceFile = info.file;
                final lc = resolveLineColumn(sourceFile, info.min);
                sourceLine = lc.line;
                sourceColumn = lc.column;
            } catch (_:Dynamic) {}
        }
        final stack = captureCallStack();
        events.push({branch: branch, pos: pos, text: text, sourceFile: sourceFile,
            sourceLine: sourceLine, sourceColumn: sourceColumn, callStack: stack});
    }

    /**
        Captures the generation-time call stack as a list of structured
        frames. Returns an empty list when the runtime cannot produce a
        usable stack. Frames are interned so a repeated deep frame costs
        one slot in the sidecar's global callStackFrames table.
    **/
    static function captureCallStack():Array<Int> {
        final out:Array<Int> = [];
        try {
            final stack = haxe.CallStack.callStack();
            for (item in stack) {
                final parsed = parseStackItem(item);
                if (parsed == null)
                    continue;
                out.push(internCallStackFrame(parsed));
            }
        } catch (_:Dynamic) {}
        return out;
    }

    static function parseStackItem(item:haxe.CallStack.StackItem):Null<StackFrame> {
        return switch (item) {
            case CFunction: null;
            case Module(m): {name: "module " + m, file: "", line: 0, column: 0};
            case FilePos(inner, file, line, column):
                final name = stackItemName(inner);
                {name: name, file: file, line: line, column: (column == null ? 0 : column)};
            case Method(classname, method): {name: classname + "." + method, file: "", line: 0, column: 0};
            case LocalFunction(name): {name: "<local#" + (name == null ? "?" : Std.string(name)) + ">", file: "", line: 0, column: 0};
        };
    }

    static function stackItemName(item:haxe.CallStack.StackItem):String {
        return switch (item) {
            case CFunction: "<cfunction>";
            case Module(m): "module " + m;
            case FilePos(inner, file, line, column):
                final n = stackItemName(inner);
                n == "" ? file : n;
            case Method(classname, method): classname + "." + method;
            case LocalFunction(name): "<local#" + (name == null ? "?" : Std.string(name)) + ">";
        };
    }

    /**
        Lenient matching for when upstream text transforms (paren-strip,
        whitespace reflow) make the exact substring fail. Strips parens
        and whitespace from both sides and retries the substring search.
        This is a fallback; the exact (faster) path runs first.
    **/
    static function matchLenient(line:String, text:String):Bool {
        if (text.length == 0 || line.length == 0)
            return false;
        final normLine = normalizeForMatch(line);
        final normText = normalizeForMatch(text);
        if (normText.length == 0 || normLine.length == 0)
            return false;
        return normLine.indexOf(normText) >= 0;
    }

    static function normalizeForMatch(s:String):String {
        final out = new StringBuf();
        var i = 0;
        while (i < s.length) {
            final c = s.charAt(i);
            if (c != "(" && c != ")" && c != " " && c != "	" && c != "")
                out.add(c);
            i++;
        }
        return out.toString();
    }

    /**
        Resolves a 1-based line and column from a byte offset into a source
        file. Offsets come from Context.getPosInfos(pos).min, measured in the
        same code units as sys.io.File.getContent().length. Returns (0,0)
        when the file cannot be read or the offset is out of range, so the
        caller never guesses a position it cannot prove.
    **/
    static function resolveLineColumn(file:Null<String>, offset:Int):{line:Int, column:Int} {
        if (file == null || file == "" || offset < 0)
            return {line: 0, column: 0};
        try {
            final content = sys.io.File.getContent(file);
            if (offset > content.length)
                return {line: 0, column: 0};
            var line = 1;
            var lineStart = 0;
            var i = 0;
            while (i < offset) {
                if (content.charCodeAt(i) == 10) {
                    line++;
                    lineStart = i + 1;
                }
                i++;
            }
            return {line: line, column: offset - lineStart + 1};
        } catch (_:Dynamic) {
            return {line: 0, column: 0};
        }
    }

    /**
        Finalizes the mapping for a generated file whose content is already
        in its final (post-wrap) form. This is the entry point used by
        targets that do not fold long lines (Kotlin, Swift, Dart).
    **/
    public static function finalizeFile(filePath:String, content:String):Null<EmitOriginMap> {
        final wrappedLines = content.split("\n");
        final identity:Array<Int> = [for (i in 0...wrappedLines.length) i];
        return finalizeFileImpl(filePath, content, wrappedLines, identity);
    }

    /**
        Finalizes the mapping for a generated file that was wrapped after
        recording. originalContent is the pre-wrap text (events were recorded
        against it), wrappedContent is the final text, and foldMap maps each
        wrapped line index back to the original line index it came from. This
        is the entry point used by the Rust target, whose wrapGeneratedSource
        splits over-long lines at top-level commas after recording.
    **/
    public static function finalizeFileWithFold(filePath:String, originalContent:String,
            wrappedContent:String, foldMap:Array<Int>):Null<EmitOriginMap> {
        final wrappedLines = wrappedContent.split("\n");
        return finalizeFileImpl(filePath, originalContent, wrappedLines, foldMap);
    }

    static function finalizeFileImpl(filePath:String, originalContent:String,
            wrappedLines:Array<String>, foldMap:Array<Int>):Null<EmitOriginMap> {
        if (!enabled || events.length == 0)
            return null;
        final header = captureHeader();
        final originalLines = originalContent.split("\n");

        // Derive expected Haxe source-file suffix from the output path.
        // modulePath("boring.WidenedFieldNonNull") produces
        // "boring/WidenedFieldNonNull.kt"; the Haxe source lives at
        // "<root>/boring/WidenedFieldNonNull.hx".  Strip any leading
        // "../" segments (test modules) and the .kt extension, then
        // match event source files by suffix.
        var relPath = filePath;
        while (StringTools.startsWith(relPath, "../")) {
            relPath = relPath.substr(3);
        }
        // Strip the generated file's own extension generically: the
        // output may be .kt, .swift, .rs or .dart depending on the target.
        final lastSlash = relPath.lastIndexOf("/");
        final lastDot = relPath.lastIndexOf(".");
        if (lastDot > lastSlash)
            relPath = relPath.substr(0, lastDot);
        final expectedSourceSuffix = "/" + relPath + ".hx";

        // Collect the subset of events whose source file belongs to this
        // module.  Events without a source file (pos == null at record
        // time) are included as a safety net; they are rare and harmless.
        final fileEvents:Array<{event:EmitEvent, globalIndex:Int}> = [];
        var ei = 0;
        while (ei < events.length) {
            final evt = events[ei];
            final sf = evt.sourceFile;
            if (sf == null || StringTools.endsWith(sf, expectedSourceSuffix)) {
                fileEvents.push({event: evt, globalIndex: ei});
            }
            ei++;
        }

        // used tracks consumption by the event's position in the global
        // array so that the cursor logic (j+1) still advances sensibly
        // across the filtered subset.
        final used:Map<Int, Bool> = new Map();
        for (fe in fileEvents) {
            used.set(fe.globalIndex, false);
        }

        // Match events against the ORIGINAL (pre-fold) lines, producing a
        // per-original-line mapping. Folding is then applied by remapping
        // each wrapped line through foldMap.
        final originalMappings:Array<Null<EmitLineMapping>> = [];
        var li = 0;
        while (li < originalLines.length) {
            originalMappings.push(null);
            li++;
        }

        var cursor = 0;
        var oi = 0;
        while (oi < originalLines.length) {
            if (cursor >= fileEvents.length)
                break;
            var j = cursor;
            while (j < fileEvents.length) {
                if (!used.get(fileEvents[j].globalIndex)) {
                    final event = fileEvents[j].event;
                    final trimmedLine = StringTools.trim(originalLines[oi]);
                    final trimmedText = StringTools.trim(event.text);
                    if (trimmedLine.length > 0 && trimmedText.length > 0
                        && (trimmedLine.indexOf(trimmedText) >= 0
                            || matchLenient(trimmedLine, trimmedText))) {
                        final frameId = internFrame(event.branch);
                        var sourceFileId = -1;
                        var sourceStart = 0;
                        var sourceEnd = 0;
                        var sourceLine = 0;
                        var sourceColumn = 0;
                        if (event.pos != null) {
                            final info = Context.getPosInfos(event.pos);
                            sourceFileId = internSourceFile(info.file);
                            sourceStart = info.min;
                            sourceEnd = info.max;
                            sourceLine = event.sourceLine;
                            sourceColumn = event.sourceColumn;
                        }
                        originalMappings[oi] = {
                            frameId: frameId,
                            sourceFileId: sourceFileId,
                            sourceStart: sourceStart,
                            sourceEnd: sourceEnd,
                            sourceLine: sourceLine,
                            sourceColumn: sourceColumn,
                            callStack: event.callStack.copy(),
                            origin: "exact",
                            inheritedFrom: -1
                        };
                        used.set(fileEvents[j].globalIndex, true);
                        cursor = j + 1;
                        break;
                    }
                }
                j++;
            }
            oi++;
        }

        // Remap original-line mappings onto wrapped-line indices via foldMap.
        final lineMappings:Array<Null<EmitLineMapping>> = [];
        var wi = 0;
        while (wi < wrappedLines.length) {
            var mapping:Null<EmitLineMapping> = null;
            if (wi < foldMap.length) {
                final origIndex = foldMap[wi];
                if (origIndex >= 0 && origIndex < originalMappings.length)
                    mapping = originalMappings[origIndex];
            }
            lineMappings.push(mapping);
            wi++;
        }

        // Backfill every no-event line from the nearest preceding exact
        // mapping so that, for any file with at least one mapped line, every
        // generated line carries a record. Inherited entries are cloned
        // (never aliased) and explicitly marked "inherited" so they cannot
        // masquerade as exact event matches.
        var wi2 = 0;
        var nearest:Null<EmitLineMapping> = null;
        var nearestLine = -1;
        while (wi2 < lineMappings.length) {
            final existing = lineMappings[wi2];
            if (existing != null) {
                nearest = existing;
                nearestLine = wi2;
            } else if (nearest != null) {
                lineMappings[wi2] = {
                    frameId: nearest.frameId,
                    sourceFileId: nearest.sourceFileId,
                    sourceStart: nearest.sourceStart,
                    sourceEnd: nearest.sourceEnd,
                    sourceLine: nearest.sourceLine,
                    sourceColumn: nearest.sourceColumn,
                    callStack: nearest.callStack.copy(),
                    origin: "inherited",
                    inheritedFrom: nearestLine
                };
            }
            wi2++;
        }

        return new EmitOriginMap(filePath, header.revision, header.haxeVersion,
            header.defines, sourcePaths.copy(), frames.copy(), callStackFrames.copy(),
            lineMappings, new Map());
    }

    public static function reset():Void {
        events.resize(0);
        sourcePathIds = new Map();
        sourcePaths.resize(0);
        frameIds = new Map();
        frames.resize(0);
        callStackFrameIds = new Map();
        callStackFrames.resize(0);
        capturedRevision = null;
        capturedHaxeVersion = null;
        capturedDefines = null;
        enabled = false;
    }

    static function captureHeader():{revision:String, haxeVersion:String, defines:Map<String, String>} {
        if (capturedRevision == null)
            capturedRevision = resolveRevision();
        if (capturedHaxeVersion == null) {
            final raw = Context.getDefines();
            final ver = raw.get("haxe_ver");
            capturedHaxeVersion = (ver != null && ver != "") ? ver : "unknown";
        }
        if (capturedDefines == null) {
            capturedDefines = new Map();
            final raw = Context.getDefines();
            for (key in raw.keys())
                capturedDefines.set(key, raw.get(key));
        }
        return {
            revision: capturedRevision,
            haxeVersion: capturedHaxeVersion,
            defines: capturedDefines
        };
    }

    static function resolveRevision():String {
        final defined = Context.definedValue("boring-revision");
        if (defined != null && defined != "")
            return defined;
        try {
            final proc = new sys.io.Process("git", ["-C", Sys.getCwd(), "rev-parse", "HEAD"]);
            final output = proc.stdout.readAll().toString();
            proc.close();
            final trimmed = StringTools.trim(output);
            if (trimmed.length > 0)
                return trimmed;
        } catch (_:Dynamic) {}
        return "unknown";
    }
}

private typedef EmitEvent = {
    final branch:String;
    final pos:Null<Position>;
    final text:String;
    final sourceFile:Null<String>;
    final sourceLine:Int;
    final sourceColumn:Int;
    final callStack:Array<Int>;
};

#end
