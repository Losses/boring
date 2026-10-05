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
    host conditioning: the six FileManager helpers accept Foundation on
    Apple SDKs (which do not expose FoundationEssentials as a top-level
    module), and the env helpers use the Windows `CRT` module (the Swift
    overlay of ucrt that swiftlang toolchains ship since 5.3; there is
    no MSVCRT module in 6.x SDKs). Foundation's `fileExists` takes its
    directory probe as `ObjCBool` where FoundationEssentials takes
    `Bool`, so Fs.isDirectory carries a separate arm body per module.
    The SwiftPM package ships the
    swift-system dependency, and only files that reference std.Fs import
    SystemPackage (the calling file's own `import` block).
**/
class SwiftHostEdges {
    /** Host-edge keys in emission order. */
    public static final KEYS = [
        "Env.get",
        "Env.set",
        "Env.remove",
        "Fs.exists",
        "Fs.isDirectory",
        "Fs.error",
        "Fs.readText",
        "Fs.writeText",
        "Fs.appendText",
        "Fs.makeDirs",
        "Fs.readDir",
        "Fs.deleteFile",
        "Fs.rename",
        "Process.run",
        "Process.exit",
        "Process.platform"
    ];

    /** The Swift file-scope helper behind each key. */
    public static function helperName(key:String):String {
        return switch (key) {
            case "Env.get": "boringEnvGet";
            case "Env.set": "boringEnvSet";
            case "Env.remove": "boringEnvRemove";
            case "Fs.exists": "boringFsExists";
            case "Fs.isDirectory": "boringFsIsDirectory";
            case "Fs.error": "boringFsError";
            case "Fs.readText": "boringFsReadText";
            case "Fs.writeText": "boringFsWriteText";
            case "Fs.appendText": "boringFsAppendText";
            case "Fs.makeDirs": "boringFsMakeDirs";
            case "Fs.readDir": "boringFsReadDir";
            case "Fs.deleteFile": "boringFsDeleteFile";
            case "Fs.rename": "boringFsRename";
            case "Process.run": "boringProcessRun";
            case "Process.exit": "boringProcessExit";
            case "Process.platform": "boringProcessPlatform";
            default: "boringUnknownEdge";
        };
    }

    /** Whether the helper throws on failure (features/06 mapping). */
    public static function throws(key:String):Bool {
        return switch (key) {
            case "Fs.readText" | "Fs.writeText" | "Fs.appendText" | "Fs.makeDirs" | "Fs.readDir" | "Fs.deleteFile" | "Fs.rename": true;
            case _: false;
        };
    }

    /** Whether the helper needs the swift-system package import. */
    public static function needsSystemPackage(key:String):Bool {
        return key == "Fs.appendText";
    }

    public static function needsFoundationEssentials(key:String):Bool {
        return switch (key) {
            case "Fs.exists" | "Fs.isDirectory" | "Fs.error" | "Fs.rename" | "Fs.readText" | "Fs.writeText" | "Fs.makeDirs" | "Fs.readDir" | "Fs.deleteFile": true;
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
            case "Fs.error": FS_ERROR;
            case "Fs.readText": FS_READ_TEXT;
            case "Fs.writeText": FS_WRITE_TEXT;
            case "Fs.appendText": FS_APPEND_TEXT;
            case "Fs.makeDirs": FS_MAKE_DIRS;
            case "Fs.readDir": FS_READ_DIR;
            case "Fs.deleteFile": FS_DELETE_FILE;
            case "Fs.rename": FS_RENAME;
            case "Process.run": PROCESS_RUN;
            case "Process.exit": PROCESS_EXIT;
            case "Process.platform": PROCESS_PLATFORM;
            default: null;
        };
    }

    static final PROCESS_EXIT = '
private func boringProcessExit(_ code: Int32) -> Never {
    #if canImport(Darwin)
    Darwin.exit(code)
    #elseif canImport(Glibc)
    Glibc.exit(code)
    #elseif canImport(CRT)
    CRT.exit(code)
    #else
    fatalError("std.Process.exit is not available on this host")
    #endif
}
';

    static final PROCESS_PLATFORM = '
private func boringProcessPlatform() -> String {
    #if os(macOS)
    return "darwin"
    #elseif os(Windows)
    return "windows"
    #else
    return "linux"
    #endif
}
';

    static final ENV_GET = '
private func boringEnvGet(_ key: String) -> String? {
    #if canImport(Glibc) || canImport(Darwin)
    return key.withCString { k in
        guard let value = getenv(k) else { return nil }
        return String(cString: value)
    }
    #elseif canImport(CRT)
    return key.withCString { k in
        var buffer: UnsafeMutablePointer<CChar>? = nil
        var count: Int = 0
        if _dupenv_s(&buffer, &count, k) == 0, let buffer {
            defer { free(buffer) }
            return String(cString: buffer)
        }
        return nil
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
    #elseif canImport(CRT)
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
    #elseif canImport(CRT)
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
    #if canImport(FoundationEssentials) || canImport(Darwin)
    return FileManager.default.fileExists(atPath: path)
    #else
    return false
    #endif
}
';

    static final FS_IS_DIRECTORY = '
private func boringFsIsDirectory(_ path: String) -> Bool {
    #if canImport(FoundationEssentials) || canImport(Darwin)
    #if canImport(FoundationEssentials)
    var isDirectory = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory
    #else
    var isDirectory = ObjCBool(false)
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    #endif
    #else
    return false
    #endif
}
';

    static final FS_ERROR = '
private func boringFsError(_ operation: String, _ path: String, _ error: Error) -> FsException {
    #if canImport(FoundationEssentials) || canImport(Darwin)
    let ns = error as NSError
    let detail = ns.localizedDescription
    #if canImport(Darwin)
    if ns.domain == NSCocoaErrorDomain {
        switch ns.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return FsException(FsError.notFound(operation: operation, path: path, nativeDetail: detail))
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return FsException(FsError.permissionDenied(operation: operation, path: path, nativeDetail: detail))
        case NSFileWriteFileExistsError:
            return FsException(FsError.alreadyExists(operation: operation, path: path, nativeDetail: detail))
        case NSFileWriteIsDirectoryError:
            return FsException(FsError.isDirectory(operation: operation, path: path, nativeDetail: detail))
        default:
            break
        }
    }
    #endif
    if ns.domain == NSPOSIXErrorDomain {
        switch Int32(ns.code) {
        case ENOENT:
            return FsException(FsError.notFound(operation: operation, path: path, nativeDetail: detail))
        case ENOTDIR:
            return FsException(FsError.notDirectory(operation: operation, path: path, nativeDetail: detail))
        case EACCES, EPERM:
            return FsException(FsError.permissionDenied(operation: operation, path: path, nativeDetail: detail))
        case EEXIST:
            return FsException(FsError.alreadyExists(operation: operation, path: path, nativeDetail: detail))
        case EINVAL, ENAMETOOLONG:
            return FsException(FsError.invalidInput(operation: operation, path: path, nativeDetail: detail))
        case EISDIR:
            return FsException(FsError.isDirectory(operation: operation, path: path, nativeDetail: detail))
        default:
            break
        }
    }
    return FsException(FsError.other(operation: operation, path: path, nativeDetail: detail))
    #else
    return FsException(FsError.other(operation: operation, path: path, nativeDetail: String(describing: error)))
    #endif
}
';

    static final FS_READ_TEXT = '
private func boringFsReadText(_ path: String) throws -> String {
    #if canImport(FoundationEssentials) || canImport(Darwin)
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return String(decoding: data, as: UTF8.self)
    } catch {
        throw boringFsError("readText", path, error)
    }
    #else
    throw FsException(FsError.unavailable(operation: "readText", path: path))
    #endif
}
';

    static final FS_WRITE_TEXT = '
private func boringFsWriteText(_ path: String, _ data: String) throws {
    #if canImport(FoundationEssentials) || canImport(Darwin)
    do {
        let bytes = Data(Array(data.utf8))
        try bytes.write(to: URL(fileURLWithPath: path))
    } catch {
        throw boringFsError("writeText", path, error)
    }
    #else
    throw FsException(FsError.unavailable(operation: "writeText", path: path))
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
        throw boringFsError("appendText", path, error)
    }
    #else
    throw FsException(FsError.unavailable(operation: "appendText", path: path))
    #endif
}
';

    static final FS_MAKE_DIRS = '
private func boringFsMakeDirs(_ path: String) throws {
    #if canImport(FoundationEssentials) || canImport(Darwin)
    do {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    } catch {
        throw boringFsError("makeDirs", path, error)
    }
    #else
    throw FsException(FsError.unavailable(operation: "makeDirs", path: path))
    #endif
}
';

    static final FS_READ_DIR = '
private func boringFsReadDir(_ path: String) throws -> [String] {
    #if canImport(FoundationEssentials) || canImport(Darwin)
    do {
        return try FileManager.default.contentsOfDirectory(atPath: path)
    } catch {
        throw boringFsError("readDir", path, error)
    }
    #else
    throw FsException(FsError.unavailable(operation: "readDir", path: path))
    #endif
}
';

    static final FS_DELETE_FILE = '
private func boringFsDeleteFile(_ path: String) throws {
    #if canImport(FoundationEssentials) || canImport(Darwin)
    do {
        try FileManager.default.removeItem(atPath: path)
    } catch {
        throw boringFsError("deleteFile", path, error)
    }
    #else
    throw FsException(FsError.unavailable(operation: "deleteFile", path: path))
    #endif
}
';

    static final FS_RENAME = '
private func boringFsRename(_ from: String, _ to: String) throws {
    #if canImport(Glibc)
    let result = from.withCString { source in to.withCString { target in Glibc.rename(source, target) } }
    if result != 0 { throw boringFsError("rename", from, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)) }
    #elseif canImport(Darwin)
    let result = from.withCString { source in to.withCString { target in Darwin.rename(source, target) } }
    if result != 0 { throw boringFsError("rename", from, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)) }
    #elseif canImport(WinSDK)
    let source = Array(from.utf16) + [UInt16(0)]
    let target = Array(to.utf16) + [UInt16(0)]
    let result = source.withUnsafeBufferPointer { s in
        target.withUnsafeBufferPointer { t in
            MoveFileExW(s.baseAddress, t.baseAddress, DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        }
    }
    if result == 0 { throw FsException(FsError.other(operation: "rename", path: from, nativeDetail: to + ": rename failed")) }
    #else
    throw FsException(FsError.unavailable(operation: "rename", path: from))
    #endif
}
';

    static final PROCESS_RUN = '
private func boringProcessRun(_ command: String, _ args: TiqianArray<String>, _ cwd: String, _ env: TiqianArray<ProcessEnv>) throws -> ProcessResult {
    #if canImport(Foundation)
    let fm = FileManager.default
    let task = Foundation.Process()
    var variables = ProcessInfo.processInfo.environment
    for entry in env { variables[entry.name] = entry.value }
    task.environment = variables
    task.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
    var executable = command
    if !command.contains("/") && !command.contains("\\\\") {
        let separator: Character = variables["PATH"]?.contains(";") == true ? ";" : ":"
        for directory in (variables["PATH"] ?? "").split(separator: separator) {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true).appendingPathComponent(command).path
            if fm.isExecutableFile(atPath: candidate) { executable = candidate; break }
        }
    }
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = args.items
    let stdoutURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let stderrURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    guard fm.createFile(atPath: stdoutURL.path, contents: nil), fm.createFile(atPath: stderrURL.path, contents: nil) else {
        throw BoringException(message: command + ": output file creation failed")
    }
    defer { try? fm.removeItem(at: stdoutURL); try? fm.removeItem(at: stderrURL) }
    do {
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer { stdoutHandle.closeFile(); stderrHandle.closeFile() }
        task.standardOutput = stdoutHandle
        task.standardError = stderrHandle
        try task.run()
        task.waitUntilExit()
        return ProcessResult(code: task.terminationStatus,
            stdout: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
            stderr: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self))
    } catch {
        throw BoringException(message: command + ": " + String(describing: error))
    }
    #else
    throw BoringException(message: "std.Process is not available on this host")
    #endif
}
';
}
#end
