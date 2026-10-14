#if (macro || reflaxe_runtime)
package;

import haxe.macro.Context;
import haxe.macro.Expr.Position;
import EmitOriginMap.EmitLineMapping;
import EmitOriginMap;
import EmitOriginMap.EmitResolution;
import EmitOriginMap.StackFrame;
import EmitOriginMap.EmitCoerceEvent;
import EmitOriginMap.EmitReferEvent;

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

    static var coerceEvents:Array<EmitCoerceEvent> = [];
    static var referEvents:Array<{symbol:String, fromUnit:String, resolve:Void->Bool}> = [];
    static var currentModule:Null<String> = null;

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
        coerceEvents.resize(0);
        referEvents.resize(0);
        capturedRevision = null;
        capturedHaxeVersion = null;
        capturedDefines = null;
    }

    /**
        Sets the module currently being lowered, used to attribute a
        coercion whose Haxe position is synthesized (a @:build macro)
        and therefore carries no usable .hx source file.
    **/
    public static function setCurrentModule(module:String):Void {
        currentModule = module;
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
            if (c != "(" && c != ")" && c != " " && c != "	" && c != "
")
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
        Records a coercion event. A real operator (!!, !, == true, ?., .) is
        recorded when a transform actually changes the text; operation=null
        records an ablated/pass-through no-op so the invariant checker can
        flag a MaybeAbsent value that reached a non-absent destination without
        an unwrap. pos is the Haxe source position of the lowered value (null
        when unavailable).
    **/
    public static function recordCoerce(pos:Null<Position>, role:String, presence:String,
            admitsAbsence:Bool, operation:Null<String>):Void {
        if (!enabled)
            return;
        var sourceFile:Null<String> = null;
        var line = 0;
        var column = 0;
        if (pos != null) {
            try {
                final info = Context.getPosInfos(pos);
                sourceFile = info.file;
                final lc = resolveLineColumn(sourceFile, info.min);
                line = lc.line;
                column = lc.column;
            } catch (_:Dynamic) {}
        }
        var module:Null<String> = null;
        if (sourceFile == null || !StringTools.endsWith(sourceFile, ".hx"))
            module = currentModule;
        coerceEvents.push({line: line, column: column, role: role, presence: presence,
            admitsAbsence: admitsAbsence, operation: operation, sourceFile: sourceFile,
            module: module, genLine: 0, genColumn: 0});
    }

    /**
        Registers a Rust symbol reference as a deferred event. The resolve
        thunk runs only at writeReferEvents() time (after RustSymbols.checkAll),
        so resolved reflects the final definition state rather than the
        pre-scan state. A passing build guarantees every thunk resolves true.
    **/
    public static function recordRefer(symbol:String, fromUnit:String, resolve:Void->Bool):Void {
        if (!enabled)
            return;
        referEvents.push({symbol: symbol, fromUnit: fromUnit, resolve: resolve});
    }

    /**
        Writes the global Rust refer sidecar after checkAll() has resolved
        every reference. Returns the JSON string, or null when disabled or no
        refer events were recorded. Refer events carry no Haxe source position,
        so line/column are 0 and the per-file tables stay empty.
    **/
    public static function writeReferEvents():Null<String> {
        if (!enabled || referEvents.length == 0)
            return null;
        final header = captureHeader();
        final resolved:Array<EmitReferEvent> = [];
        for (re in referEvents)
            resolved.push({line: 0, symbol: re.symbol, fromUnit: re.fromUnit, resolved: re.resolve()});
        final map = new EmitOriginMap("refer.emit-origin.json", header.revision,
            header.haxeVersion, header.defines, [], [], [], [], new Map(), [], resolved);
        return map.write();
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
        if (!enabled || (events.length == 0 && coerceEvents.length == 0))
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

        // Coercion events carry their own Haxe source file. A coercion with
        // no source position cannot be attributed to any file, so it is
        // dropped here rather than duplicated into every sidecar. Refer
        // events never land here: written once via writeReferEvents().
        final fileCoerceEvents:Array<EmitCoerceEvent> = [];
        for (ce in coerceEvents) {
            final sf = ce.sourceFile;
            final byFile = sf != null && StringTools.endsWith(sf, expectedSourceSuffix);
            final byModule = ce.module != null && ce.module.split(".").join("/") == relPath;
            if (byFile || byModule) {
                fileCoerceEvents.push(ce);
            }
        }
        assignGeneratedPositions(filePath, originalContent, fileCoerceEvents);

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
            lineMappings, new Map(), fileCoerceEvents, []);
    }

    /**
        Assigns the generated file 1-based line/column to each conversion
        coercion event (Kotlin "!!"/"== true", Swift "!"). Pass-through events
        ("?." and ".") keep 0 because the checker never scans them. Matching is
        positional per file: conversion events are recorded in left-to-right
        emission order, so the k-th conversion event of an operation maps to
        the k-th such token scanned here. Tokens with no event (the bypass
        probe is recorded via record(), not recordCoerce()) stay unmatched,
        which is what lets direction 2 flag them.
    **/
    static function assignGeneratedPositions(filePath:String, originalContent:String,
            coerceEvents:Array<EmitCoerceEvent>):Void {
        final isSwift = StringTools.endsWith(filePath, ".swift");
        if (!StringTools.endsWith(filePath, ".kt") && !isSwift)
            return;
        final tokens:Array<{line:Int, column:Int, operation:String}> = [];
        scanConversionTokens(originalContent, isSwift, tokens);

        // Group-zip per operation: conversion events are recorded in emission
        // (source) order and tokens are scanned in generated order. A single
        // coerce can emit the same token several times (template reuse, e.g.
        // String.fromCharCode rendered three times), so a naive 1:1 zip shifts
        // every downstream line. Events sharing one Haxe source line form one
        // group and consume exactly one generated-line token group, so zip the
        // two group sequences and assign every event in group k the generated
        // line of token group k. (TemplateReuseGroupZip)
        final ops = ["!!", "== true", "!"];
        for (op in ops) {
            final tokenGroups:Array<{line:Int, column:Int}> = [];
            var ti = 0;
            while (ti < tokens.length) {
                if (tokens[ti].operation != op) { ti++; continue; }
                final line = tokens[ti].line;
                tokenGroups.push({line: line, column: tokens[ti].column});
                while (ti < tokens.length && tokens[ti].operation == op && tokens[ti].line == line)
                    ti++;
            }
            if (tokenGroups.length == 0)
                continue;
            var gi = 0;
            var ci = 0;
            while (ci < coerceEvents.length && gi < tokenGroups.length) {
                if (coerceEvents[ci].operation != op) { ci++; continue; }
                final srcLine = coerceEvents[ci].line;
                while (ci < coerceEvents.length && coerceEvents[ci].operation == op
                        && coerceEvents[ci].line == srcLine) {
                    coerceEvents[ci].genLine = tokenGroups[gi].line;
                    coerceEvents[ci].genColumn = tokenGroups[gi].column;
                    ci++;
                }
                gi++;
            }
        }
    }

    /** Scans generated source for conversion tokens, skipping comments and
        string/char literals so they never masquerade as coercion output.
        Column is 1-based and mirrors the checker's convention: the first "!"
        of "!!", the first "=" of "== true", and the "!" of Swift force-unwrap. **/
    static function scanConversionTokens(content:String, isSwift:Bool,
            tokens:Array<{line:Int, column:Int, operation:String}>):Void {
        final n = content.length;
        var i = 0;
        var line = 1;
        var col = 1;
        while (i < n) {
            final code = content.charCodeAt(i);
            final nxtCode = i + 1 < n ? content.charCodeAt(i + 1) : -1;

            if (code == 47 && nxtCode == 47) {
                while (i < n && content.charCodeAt(i) != 10) { i++; col++; }
                continue;
            }
            if (code == 47 && nxtCode == 42) {
                var depth = 1;
                i += 2; col += 2;
                while (i < n && depth > 0) {
                    final a = content.charCodeAt(i);
                    final b = i + 1 < n ? content.charCodeAt(i + 1) : -1;
                    if (a == 47 && b == 42) { depth++; i += 2; col += 2; }
                    else if (a == 42 && b == 47) { depth--; i += 2; col += 2; }
                    else if (a == 10) { i++; line++; col = 1; }
                    else { i++; col++; }
                }
                continue;
            }
            if (code == 34 && i + 2 < n && content.charCodeAt(i + 1) == 34 && content.charCodeAt(i + 2) == 34) {
                i += 3; col += 3;
                while (i < n) {
                    if (i + 2 < n && content.charCodeAt(i) == 34 && content.charCodeAt(i + 1) == 34 && content.charCodeAt(i + 2) == 34) { i += 3; col += 3; break; }
                    if (content.charCodeAt(i) == 10) { i++; line++; col = 1; }
                    else { i++; col++; }
                }
                continue;
            }
            if (code == 34) {
                i++; col++;
                while (i < n) {
                    final ch = content.charCodeAt(i);
                    if (ch == 92) { i += 2; col += 2; continue; }
                    if (ch == 34) { i++; col++; break; }
                    if (ch == 10) { i++; line++; col = 1; }
                    else { i++; col++; }
                }
                continue;
            }
            if (code == 39) {
                i++; col++;
                while (i < n) {
                    final ch = content.charCodeAt(i);
                    if (ch == 92) { i += 2; col += 2; continue; }
                    if (ch == 39) { i++; col++; break; }
                    if (ch == 10) { i++; line++; col = 1; }
                    else { i++; col++; }
                }
                continue;
            }

            if (!isSwift) {
                if (code == 33 && nxtCode == 33) {
                    tokens.push({line: line, column: col, operation: "!!"});
                    i += 2; col += 2;
                    continue;
                }
                if (code == 61 && nxtCode == 61) {
                    var k = i + 2;
                    while (k < n && (content.charCodeAt(k) == 32 || content.charCodeAt(k) == 9)) k++;
                    if (k + 4 <= n && content.substr(k, 4) == "true") {
                        final afterCode = k + 4 < n ? content.charCodeAt(k + 4) : -1;
                        if (afterCode < 0 || !isIdentCharCode(afterCode)) {
                            tokens.push({line: line, column: col, operation: "== true"});
                            col += (k + 4) - i;
                            i = k + 4;
                            continue;
                        }
                    }
                }
            } else {
                if (code == 33 && nxtCode != 61 && isPostfixBang(content, i)) {
                    tokens.push({line: line, column: col, operation: "!"});
                    i++; col++;
                    continue;
                }
            }

            if (code == 10) { i++; line++; col = 1; }
            else { i++; col++; }
        }
    }

    /** True when the "!" at i is a postfix force-unwrap (follows an identifier
        or a closing bracket/paren/brace/dot/quote after skipping whitespace). **/
    static function isPostfixBang(content:String, i:Int):Bool {
        var j = i - 1;
        while (j >= 0) {
            final ch = content.charCodeAt(j);
            if (ch != 32 && ch != 9 && ch != 10) break;
            j--;
        }
        if (j < 0) return false;
        final p = content.charCodeAt(j);
        return isIdentCharCode(p) || p == 41 || p == 93 || p == 125 || p == 46 || p == 34 || p == 39 || p == 62;
    }

    static function isIdentCharCode(code:Int):Bool {
        return (code >= 97 && code <= 122) || (code >= 65 && code <= 90)
            || (code >= 48 && code <= 57) || code == 95;
    }

    public static function reset():Void {
        events.resize(0);
        coerceEvents.resize(0);
        referEvents.resize(0);
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
