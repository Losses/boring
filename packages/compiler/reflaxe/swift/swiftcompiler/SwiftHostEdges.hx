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
        return switch (key) {
            case "Fs.readText" | "Fs.writeText" | "Fs.appendText": true;
            case _: false;
        };
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
    #if canImport(Glibc) || canImport(Darwin)
    return path.withCString { p in access(p, F_OK) == 0 }
    #elseif canImport(MSVCRT)
    // _access mode 0 tests existence (Microsoft Learn, _access).
    return path.withCString { p in _access(p, 0) == 0 }
    #else
    return false
    #endif
}
';

    static final FS_IS_DIRECTORY = '
private func boringFsIsDirectory(_ path: String) -> Bool {
    #if canImport(Glibc) || canImport(Darwin)
    var st = stat()
    return path.withCString { p in stat(p, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR }
    #elseif canImport(WinSDK)
    // GetFileAttributesW reports the directory bit (Microsoft Learn,
    // GetFileAttributesW and File Attribute Constants).
    let wide = Array(path.utf16)
    let attrs = wide.withUnsafeBufferPointer { GetFileAttributesW($0.baseAddress) }
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0
    #else
    return false
    #endif
}
';

    static final FS_READ_TEXT = '
private func boringFsReadText(_ path: String) throws -> String {
    #if canImport(SystemPackage)
    do {
        let handle = try FileDescriptor.open(FilePath(path), .readOnly)
        return try handle.closeAfter {
            var data: [UInt8] = []
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = try chunk.withUnsafeMutableBytes { try handle.read(into: $0) }
                if count == 0 { break }
                data.append(contentsOf: chunk[0..<count])
            }
            return String(decoding: data, as: UTF8.self)
        }
    } catch {
        throw BoringException(message: path + ": " + String(describing: error))
    }
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}
';

    static final FS_WRITE_TEXT = '
private func boringFsWriteText(_ path: String, _ data: String) throws {
    #if canImport(SystemPackage)
    do {
        let handle = try FileDescriptor.open(FilePath(path), .writeOnly,
            options: [.create, .truncate], permissions: FilePermissions(rawValue: 0o644))
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
    #if canImport(Glibc) || canImport(Darwin)
    if path.isEmpty { return }
    var prefix = path.hasPrefix("/") ? "/" : ""
    for part in path.split(separator: "/") {
        if part.isEmpty { continue }
        prefix += part
        let rc = prefix.withCString { p in mkdir(p, 0o755) }
        if rc != 0 && errno != EEXIST {
            throw BoringException(message: path + ": " + String(cString: strerror(errno)))
        }
        prefix += "/"
    }
    #elseif canImport(WinSDK)
    // CreateDirectoryW per component (Microsoft Learn,
    // CreateDirectoryW); an existing component is not an error.
    if path.isEmpty { return }
    let chars = Array(path)
    var prefix = ""
    var i = 0
    let n = chars.count
    if n >= 2 && isAsciiLetter(chars[0]) && chars[1] == ":" {
        prefix = String(chars[0]) + ":"
        i = 2
        if i < n && (chars[i] == "/" || chars[i] == "\\\\") {
            prefix += "\\\\"
            i += 1
        }
    } else if n >= 2 && chars[0] == "\\\\" && chars[1] == "\\\\" {
        prefix = "\\\\\\\\"
        i = 2
        var separators = 0
        while i < n {
            prefix.append(chars[i])
            if chars[i] == "/" || chars[i] == "\\\\" {
                separators += 1
                if separators == 2 {
                    i += 1
                    break
                }
            }
            i += 1
        }
    } else if chars[0] == "/" || chars[0] == "\\\\" {
        prefix = "\\\\"
        i = 1
    }
    var segment = ""
    while i <= n {
        let atEnd = i == n
        let isSep = !atEnd && (chars[i] == "/" || chars[i] == "\\\\")
        if atEnd || isSep {
            if !segment.isEmpty {
                prefix += segment
                let wide = Array(prefix.utf16)
                let created = wide.withUnsafeBufferPointer { CreateDirectoryW($0.baseAddress, nil) != 0 }
                if !created {
                    let code = GetLastError()
                    if code != ERROR_ALREADY_EXISTS {
                        throw BoringException(message: path + ": Win32 error " + String(code))
                    }
                }
                prefix += "\\\\"
                segment = ""
            }
        } else {
            segment.append(chars[i])
        }
        i += 1
    }
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}

private func isAsciiLetter(_ c: Character) -> Bool {
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
}
';

    static final FS_READ_DIR = '
private func boringFsReadDir(_ path: String) throws -> [String] {
    #if canImport(Glibc) || canImport(Darwin)
    return try path.withCString { p in
        guard let dir = opendir(p) else {
            throw BoringException(message: path + ": " + String(cString: strerror(errno)))
        }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            if name != "." && name != ".." {
                names.append(name)
            }
        }
        return names
    }
    #elseif canImport(WinSDK)
    // FindFirstFileW/FindNextFileW/FindClose (Microsoft Learn): the
    // pattern is the path plus a \\* suffix, and entry names convert
    // through the UTF-16 view (String.utf16). FindClose runs on every
    // exit path through defer.
    let pattern = path.hasSuffix("\\\\") || path.hasSuffix("/") ? path + "*" : path + "\\\\*"
    let widePattern = Array(pattern.utf16)
    var data = WIN32_FIND_DATAW()
    let handle = widePattern.withUnsafeBufferPointer { FindFirstFileW($0.baseAddress, &data) }
    if handle == INVALID_HANDLE_VALUE {
        throw BoringException(message: path + ": Win32 error " + String(GetLastError()))
    }
    defer { FindClose(handle) }
    var names: [String] = []
    while true {
        let name = withUnsafePointer(to: &data.cFileName) {
            boringWideString(UnsafeRawPointer($0).assumingMemoryBound(to: UInt16.self))
        }
        if name != "." && name != ".." {
            names.append(name)
        }
        if FindNextFileW(handle, &data) == 0 {
            if GetLastError() != ERROR_NO_MORE_FILES {
                throw BoringException(message: path + ": Win32 error " + String(GetLastError()))
            }
            break
        }
    }
    return names
    #else
    throw BoringException(message: "std.Fs is not available on this host")
    #endif
}

private func boringWideString(_ units: UnsafePointer<UInt16>) -> String {
    var out: [UInt16] = []
    var p = units
    while p.pointee != 0 {
        out.append(p.pointee)
        p += 1
    }
    return String(decoding: out, as: UTF16.self)
}
';
}
#end
