#if (macro || reflaxe_runtime)
package;

import haxe.macro.Context;
import haxe.macro.Expr.Position;
import EmitOriginMap.EmitLineMapping;
import EmitOriginMap;
import EmitOriginMap.EmitResolution;

/**
    Emission-origin recording sink.

    Records the emitter branch and Haxe source position at each
    emission "push" so one generation pass can resolve every
    host-compiler diagnostic back to the emitting branch and the
    Haxe source node that produced it.

    The sink interns source file paths and frame names to
    integer ids, accumulates events during generation, and
    produces per-file compact EmitOriginMap instances at
    finalization time.
**/
class EmitSink {
    public static var enabled(default, null):Bool = false;

    static var events:Array<EmitEvent> = [];
    static var sourcePathIds:Map<String, Int> = new Map();
    static var sourcePaths:Array<String> = [];
    static var frameIds:Map<String, Int> = new Map();
    static var frames:Array<String> = [];
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

    public static function record(branch:Null<String>, pos:Null<Position>, text:Null<String>):Void {
        if (!enabled || branch == null || text == null)
            return;
        var sourceFile:Null<String> = null;
        if (pos != null) {
            try {
                sourceFile = Context.getPosInfos(pos).file;
            } catch (_:Dynamic) {}
        }
        events.push({branch: branch, pos: pos, text: text, sourceFile: sourceFile});
    }

    public static function finalizeFile(filePath:String, content:String):Null<EmitOriginMap> {
        if (!enabled || events.length == 0)
            return null;
        final header = captureHeader();
        final rawLines = content.split("\n");
        final lineMappings:Array<Null<EmitLineMapping>> = [];
        var i = 0;
        while (i < rawLines.length) {
            lineMappings.push(null);
            i++;
        }

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

        var cursor = 0;
        i = 0;
        while (i < rawLines.length) {
            if (cursor >= fileEvents.length)
                break;
            var j = cursor;
            while (j < fileEvents.length) {
                if (!used.get(fileEvents[j].globalIndex)) {
                    final event = fileEvents[j].event;
                    final trimmedLine = StringTools.trim(rawLines[i]);
                    final trimmedText = StringTools.trim(event.text);
                    if (trimmedLine.length > 0 && trimmedText.length > 0
                        && trimmedLine.indexOf(trimmedText) >= 0) {
                        final frameId = internFrame(event.branch);
                        var sourceFileId = -1;
                        var sourceStart = 0;
                        var sourceEnd = 0;
                        if (event.pos != null) {
                            final info = Context.getPosInfos(event.pos);
                            sourceFileId = internSourceFile(info.file);
                            sourceStart = info.min;
                            sourceEnd = info.max;
                        }
                        lineMappings[i] = {
                            frameId: frameId,
                            sourceFileId: sourceFileId,
                            sourceStart: sourceStart,
                            sourceEnd: sourceEnd
                        };
                        used.set(fileEvents[j].globalIndex, true);
                        cursor = j + 1;
                        break;
                    }
                }
                j++;
            }
            i++;
        }
        return new EmitOriginMap(filePath, header.revision, header.haxeVersion,
            header.defines, sourcePaths.copy(), frames.copy(), lineMappings, new Map());
    }

    public static function reset():Void {
        events.resize(0);
        sourcePathIds = new Map();
        sourcePaths.resize(0);
        frameIds = new Map();
        frames.resize(0);
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
};

#end
