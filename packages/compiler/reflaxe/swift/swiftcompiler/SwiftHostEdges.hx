package swiftcompiler;

#if (macro || reflaxe_runtime)
/**
    Host-edge helper sources of the stdlib/17 platform modules
    (docs/specs/stdlib/17-platform-modules.md). Swift lowers a static
    call on std.Env or std.Fs to a call on one of these file-scope
    functions, emitted `private` into the calling file so each generated
    file that references a platform module carries its own copy without
    colliding across files of the one Swift module. The C interop of
    every helper sits inside `#if canImport(...)` arms per the spec's
    host conditioning; the SwiftPM package ships the swift-system
    dependency, and only files that reference std.Fs import
    SystemPackage (the calling file's own `import` block).
**/
class SwiftHostEdges {
    /** Host-edge keys in emission order. */
    public static final KEYS = [
        "Env.get", "Env.set", "Env.remove",
        "Fs.exists", "Fs.isDirectory", "Fs.readText", "Fs.writeText",
        "Fs.appendText", "Fs.makeDirs", "Fs.readDir"
    ];

    /** The Swift file-scope helper behind each key. */
    public static function helperName(key:String):String {
        return switch (key) {
            case "Env.get": "boringEnvGet";
            case "Env.set": "boringEnvSet";
            case "Env.remove": "boringEnvRemove";
            case "Fs.exists": "boringFsExists";
            case "Fs.isDirectory": "boringFsIsDirectory";
            case "Fs.readText": "boringFsReadText";
            case "Fs.writeText": "boringFsWriteText";
            case "Fs.appendText": "boringFsAppendText";
            case "Fs.makeDirs": "boringFsMakeDirs";
            case "Fs.readDir": "boringFsReadDir";
            default: "boringUnknownEdge";
        };
    }

    /** Whether the helper throws on failure (features/06 mapping). */
    public static function throws(key:String):Bool {
        return switch (key) {
            case "Fs.readText" | "Fs.writeText" | "Fs.appendText" | "Fs.makeDirs" | "Fs.readDir": true;
            case _: false;
        };
    }

    /** Whether the helper needs the swift-system package import. */
    public static function needsSystemPackage(key:String):Bool {
        return key == "Fs.appendText";
    }

    public static function needsFoundationEssentials(key:String):Bool {
        return switch (key) {
            case "Fs.exists" | "Fs.isDirectory" | "Fs.readText" | "Fs.writeText" | "Fs.makeDirs" | "Fs.readDir": true;
            case _: false;
        }
    }


    /** The source text of one host-edge helper. */
    public static function source(key:String):Null<String> {
        return switch (key) {
            case "Env.get": ENV_GET;
            case "Env.set": ENV_SET;
            case "Env.remove": ENV_REMOVE;
            case "Fs.exists": FS_EXISTS;
            case "Fs.isDirectory": FS_IS_DIRECTORY;
            case "Fs.readText": FS_READ_TEXT;
            case "Fs.writeText": FS_WRITE_TEXT;
            case "Fs.appendText": FS_APPEND_TEXT;
            case "Fs.makeDirs": FS_MAKE_DIRS;
            case "Fs.readDir": FS_READ_DIR;
            default: null;
        };
    }

    static final ENV_GET = '
private func boringEnvGet(_ key: String) -> String? {
    #if canImport(Glibc) || canImport(Darwin)
    return key.withCString { k in
        guard let value = getenv(k) else { return nil }
        return String(cString: value)
    }
    #elseif canImport(MSVCRT)
    // The UCRT exports the same getenv symbol; the read goes through
    // the CRT so get and set share one environment view.
    return key.withCString { k in
        guard let value = getenv(k) else { return nil }
        return String(cString: value)
    }
    #else
    return nil
    #endif
}
';

    static final ENV_SET = '
private func boringEnvSet(_ key: String, _ value: String) {
    #if canImport(Glibc) || canImport(Darwin)
    _ = key.withCString { k in
        value.withCString { v in setenv(k, v, 1) }
    }
    #elseif canImport(MSVCRT)
    // Set goes through the CRT pair on purpose (spec stdlib/17): get
    // reads the CRT, so the write must land there too. _putenv_s
    // returns errno_t; a failing set has no observable effect here.
    _ = key.withCString { k in
        value.withCString { v in _putenv_s(k, v) }
    }
    #else
    #endif
}
';

    static final ENV_REMOVE = '
private func boringEnvRemove(_ key: String) {
    #if canImport(Glibc) || canImport(Darwin)
    _ = key.withCString { k in unsetenv(k) }
    #elseif canImport(MSVCRT)
    // The documented remove form of _putenv is the "name=" entry
    // (Microsoft Learn, _putenv/_wputenv): a name with an empty value
    // removes the variable rather than setting it.
    let pair = key + "="
    _ = pair.withCString { k in _putenv(k) }
    #else
    #endif
}
';

    static final FS_EXISTS = '
private func boringFsExists(_ path: String) -> Bool {
    #if canImport(FoundationEssentials)
    return FileManager.default.fileExists(atPath: path)
    #else
    return false
    #endif
}
';

    static final FS_IS_DIRECTORY = '
private func boringFsIsDirectory(_ path: String) -> Bool {
    #if canImport(FoundationEssentials)
    var isDirectory = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory
    #else
    return false
    #endif
}
';

    static final FS_READ_TEXT = '
private func boringFsReadText(_ path: String) throws -> String {
    #if canImport(FoundationEssentials)
    guard let data = FileManager.default.contents(atPath: path) else {
        throw BoringException(message: path + ": read failed")
    }
    return String(decoding: data, as: UTF8.self)
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}
';

    static final FS_WRITE_TEXT = '
private func boringFsWriteText(_ path: String, _ data: String) throws {
    #if canImport(FoundationEssentials)
    let bytes = Data(Array(data.utf8))
    guard FileManager.default.createFile(atPath: path, contents: bytes) else {
        throw BoringException(message: path + ": write failed")
    }
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}
';

    static final FS_APPEND_TEXT = '
private func boringFsAppendText(_ path: String, _ data: String) throws {
    #if canImport(SystemPackage)
    do {
        let handle = try FileDescriptor.open(FilePath(path), .writeOnly,
            options: [.append, .create], permissions: FilePermissions(rawValue: 0o644))
        let _ = try handle.closeAfter {
            try Array(data.utf8).withUnsafeBytes { try handle.writeAll($0) }
        }
    } catch {
        throw BoringException(message: path + ": " + String(describing: error))
    }
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}
';

    static final FS_MAKE_DIRS = '
private func boringFsMakeDirs(_ path: String) throws {
    #if canImport(FoundationEssentials)
    do {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    } catch {
        throw BoringException(message: path + ": " + String(describing: error))
    }
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}
';

    static final FS_READ_DIR = '
private func boringFsReadDir(_ path: String) throws -> [String] {
    #if canImport(FoundationEssentials)
    do {
        return try FileManager.default.contentsOfDirectory(atPath: path)
    } catch {
        throw BoringException(message: path + ": " + String(describing: error))
    }
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}
';
}
#end
