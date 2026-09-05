// Windows-arm typecheck probe of the stdlib/17 host-edge helpers
// (docs/specs/stdlib/17-platform-modules.md, "Host conditioning").
//
// The toolchain's Swift chain runs on Linux, so the canImport(MSVCRT)
// and canImport(WinSDK) arms of the std.Env and std.Fs helpers cannot
// execute here. Their verification level is (a) review against the
// documented Win32/UCRT semantics (citations inline below) and (b) this
// compile probe: the arm bodies are extracted from the emitter sources
// and compiled on Linux against stub declarations of the UCRT and Win32
// symbols they call, which type-checks every identifier, argument, and
// call shape the arms use. A Windows CI slot that compiles and runs the
// suite natively is the follow-up that upgrades this level.
//
// Stub shapes follow the swift-corelibs-foundation WinSDK overlay where
// one exists. Citations:
// - _putenv_s, _putenv / _wputenv (Microsoft Learn)
// - GetFileAttributesW and File Attribute Constants (Microsoft Learn)
// - CreateDirectoryW (Microsoft Learn)
// - FindFirstFileW / FindNextFileW / FindClose and WIN32_FIND_DATAW
//   (Microsoft Learn)
// - _access (Microsoft Learn)

// ---------------------------------------------------------------------
// Stub declarations (Linux stand-ins for the Windows SDK API set)
// ---------------------------------------------------------------------

typealias DWORD = UInt32
typealias BOOL = Int32
typealias HANDLE = UnsafeMutableRawPointer
typealias LPCWSTR = UnsafePointer<UInt16>

let INVALID_HANDLE_VALUE: HANDLE = UnsafeMutableRawPointer(bitPattern: -1)!
let INVALID_FILE_ATTRIBUTES: DWORD = 0xFFFF_FFFF
let FILE_ATTRIBUTE_DIRECTORY: DWORD = 0x10
let ERROR_ALREADY_EXISTS: DWORD = 183
let ERROR_NO_MORE_FILES: DWORD = 18

struct SECURITY_ATTRIBUTES {}

struct WIN32_FIND_DATAW {
    var cFileName: (UInt16, UInt16, UInt16)
    init(cFileName: (UInt16, UInt16, UInt16)) {
        self.cFileName = cFileName
    }
}

func FindFirstFileW(_ name: LPCWSTR?, _ data: UnsafeMutablePointer<WIN32_FIND_DATAW>?) -> HANDLE {
    return INVALID_HANDLE_VALUE
}
func FindNextFileW(_ handle: HANDLE, _ data: UnsafeMutablePointer<WIN32_FIND_DATAW>?) -> BOOL {
    return 0
}
func FindClose(_ handle: HANDLE) -> BOOL {
    return 1
}
func GetFileAttributesW(_ name: LPCWSTR?) -> DWORD {
    return INVALID_FILE_ATTRIBUTES
}
func CreateDirectoryW(_ name: LPCWSTR?, _ attrs: UnsafePointer<SECURITY_ATTRIBUTES>?) -> BOOL {
    return 0
}
func GetLastError() -> DWORD {
    return ERROR_ALREADY_EXISTS
}
func _putenv_s(_ name: UnsafePointer<CChar>, _ value: UnsafePointer<CChar>) -> Int32 {
    return 0
}
func _putenv(_ name: UnsafePointer<CChar>) -> Int32 {
    return 0
}
func getenv(_ name: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    return nil
}

// The haxe.Exception mapping the helpers raise (features/06).
class BoringException: Error {
    init(message: String) {}
}

private func isAsciiLetter(_ c: Character) -> Bool {
    return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
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

// ---------------------------------------------------------------------
// Extracted arm bodies (the #if canImport guards are stripped; each
// body is the text the emitter places inside its arm)
// ---------------------------------------------------------------------

// std.Env.get, MSVCRT arm (getenv from the UCRT).
private func boringEnvGet(_ key: String) -> String? {
    return key.withCString { k in
        guard let value = getenv(k) else { return nil }
        return String(cString: value)
    }
}

// std.Env.set, MSVCRT arm (_putenv_s; set goes through the CRT pair).
private func boringEnvSet(_ key: String, _ value: String) {
    _ = key.withCString { k in
        value.withCString { v in _putenv_s(k, v) }
    }
}

// std.Env.remove, MSVCRT arm (_putenv documented remove form "name=").
private func boringEnvRemove(_ key: String) {
    let pair = key + "="
    _ = pair.withCString { k in _putenv(k) }
}

// std.Fs.exists, MSVCRT arm (_access mode 0 tests existence).
private func boringFsExists(_ path: String) -> Bool {
    return path.withCString { p in _access(p, 0) == 0 }
}
func _access(_ name: UnsafePointer<CChar>, _ mode: Int32) -> Int32 {
    return 0
}

// std.Fs.isDirectory, WinSDK arm (GetFileAttributesW directory bit).
private func boringFsIsDirectory(_ path: String) -> Bool {
    let wide = Array(path.utf16)
    let attrs = wide.withUnsafeBufferPointer { GetFileAttributesW($0.baseAddress) }
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0
}

// std.Fs.makeDirs, WinSDK arm (CreateDirectoryW per component).
private func boringFsMakeDirs(_ path: String) throws {
    if path.isEmpty { return }
    let chars = Array(path)
    var prefix = ""
    var i = 0
    let n = chars.count
    if n >= 2 && isAsciiLetter(chars[0]) && chars[1] == ":" {
        prefix = String(chars[0]) + ":"
        i = 2
        if i < n && (chars[i] == "/" || chars[i] == "\\") {
            prefix += "\\"
            i += 1
        }
    } else if n >= 2 && chars[0] == "\\" && chars[1] == "\\" {
        prefix = "\\\\"
        i = 2
        var separators = 0
        while i < n {
            prefix.append(chars[i])
            if chars[i] == "/" || chars[i] == "\\" {
                separators += 1
                if separators == 2 {
                    i += 1
                    break
                }
            }
            i += 1
        }
    } else if chars[0] == "/" || chars[0] == "\\" {
        prefix = "\\"
        i = 1
    }
    var segment = ""
    while i <= n {
        let atEnd = i == n
        let isSep = !atEnd && (chars[i] == "/" || chars[i] == "\\")
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
                prefix += "\\"
                segment = ""
            }
        } else {
            segment.append(chars[i])
        }
        i += 1
    }
}

// std.Fs.readDir, WinSDK arm (FindFirstFileW/FindNextFileW/FindClose
// with the "\*" pattern suffix and UTF-16 conversion).
private func boringFsReadDir(_ path: String) throws -> [String] {
    let pattern = path.hasSuffix("\\") || path.hasSuffix("/") ? path + "*" : path + "\\*"
    let widePattern = Array(pattern.utf16)
    var data = WIN32_FIND_DATAW(cFileName: (0, 0, 0))
    let handle = widePattern.withUnsafeBufferPointer { FindFirstFileW($0.baseAddress, &data) }
    if handle == INVALID_HANDLE_VALUE {
        throw BoringException(message: path + ": Win32 error " + String(GetLastError()))
    }
    defer { _ = FindClose(handle) }
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
}

// Referencing every probe helper keeps the type checker over the whole
// file; the calls never run (the stubs return failure sentinels).
let _probe = { () -> Void in
    _ = boringEnvGet("PROBE_KEY")
    boringEnvSet("PROBE_KEY", "value")
    boringEnvRemove("PROBE_KEY")
    _ = boringFsExists("C:\\probe")
    _ = boringFsIsDirectory("C:\\probe")
    _ = try? boringFsMakeDirs("C:\\probe\\a\\b")
    _ = try? boringFsReadDir("C:\\probe")
}
_ = _probe
print("windows-probe-typecheck-ok")
