// The C library of the host, for the environment read below. This file is
// written on its own, without the header the generated modules carry, so
// the conditional imports live here.
#if canImport(Glibc)
import Glibc
#endif
#if canImport(Darwin)
import Darwin
#endif
#if canImport(CRT)
import CRT
#endif

/// The text of an environment variable, or nil when it is unset. The
/// platform calls match the ones the std.Env host edge uses.
func boringTestEnvText(_ key: String) -> String? {
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

/// The wall-clock budget of one test in milliseconds, read from the
/// environment on every run and never at generation time, so one generated
/// tree serves every budget. A value that is absent, unparsable, or not
/// positive falls back to 5000. The generated entry carries no runner timer
/// of its own, so this check is the only timeout a body that returned late
/// is caught by.
func boringTestTimeoutBudgetMs() -> Int {
    if let raw = boringTestEnvText("BORING_TEST_TIMEOUT_MS"), let parsed = Int(raw), parsed > 0 {
        return parsed
    }
    return 5000
}

/// The wall-clock milliseconds since the given instant. The standard
/// library clock is monotonic, so no platform timer API enters the runtime.
func boringTestElapsedMs(since start: ContinuousClock.Instant) -> Int {
    let elapsed = start.duration(to: ContinuousClock().now)
    return Int(elapsed.components.seconds) * 1000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
}

/// The results sink of the test entry (features/19): the file named by
/// BORING_TEST_RESULTS, or out/test-results/swift.jsonl when the
/// variable is unset or empty, the same default as the kotlin, rust
/// and ts hosts.
func boringTestResultsPath() -> String {
    if let fromEnv = boringTestEnvText("BORING_TEST_RESULTS"), !fromEnv.isEmpty {
        return fromEnv
    }
    return "out/test-results/swift.jsonl"
}

/// One directory level, existing or not. The platform calls match the
/// ones the std.Env host edge uses; a level that already exists is not
/// an error, so the walk only bridges a fresh tree to its first
/// record.
func boringTestMakeDir(_ dirPath: String) {
    #if canImport(Glibc) || canImport(Darwin)
    _ = mkdir(dirPath, 0777)
    #elseif canImport(CRT)
    _ = _mkdir(dirPath)
    #endif
}

/// The parent directories of the results file, created on demand so
/// the default path works on a fresh tree.
func boringTestEnsureParentDirs(of path: String) {
    var components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard components.count > 1 else {
        return
    }
    components.removeLast()
    var partial = path.hasPrefix("/") ? "" : "."
    for component in components {
        if partial == "" {
            partial = "/" + component
        } else if partial == "." {
            partial = component
        } else {
            partial = partial + "/" + component
        }
        boringTestMakeDir(partial)
    }
}

/// One record per call: the line decodes to text, appends to the
/// results file as UTF-8, and the fclose flushes, so a nonzero exit
/// still leaves every written record on disk.
func boringTestAppendResult(_ line: [UInt16]) {
    let path = boringTestResultsPath()
    boringTestEnsureParentDirs(of: path)
    guard let fp = fopen(path, "a") else {
        return
    }
    defer { _ = fclose(fp) }
    let bytes = Array(decodeUnits(line).utf8)
    bytes.withUnsafeBufferPointer { buffer in
        if let base = buffer.baseAddress {
            _ = fwrite(base, 1, buffer.count, fp)
        }
    }
}

/// The assertion failure of features/19: the canonical message in the
/// resident unit-array ABI, converted to text only at the print edge.
public struct TestFailure: Error {
    public let message: [UInt16]

    public init(message: [UInt16]) {
        self.message = message
    }
}

func decodeUnits(_ units: [UInt16]) -> String {
    return String(decoding: units, as: UTF16.self)
}

public enum Test {
    private static var currentTestId: [UInt16] = []

    // Host edges of the test entry (features/19): the runner state, the
    // raise of this language, and the results-file edge. Assertion
    // checks and scalar formatting live in TestCore, appended after
    // this enum in this same file.
    public static func currentTestIdState() -> [UInt16] {
        return Test.currentTestId
    }

    // A test this target excludes (features/19): the entry does not run
    // the body and writes the not-applicable record instead, so the id
    // stays in the cross-target set.
    public static func recordNotApplicable(_ id: String, _ name: String) {
        boringTestAppendResult(TestCore.notApplicableLine(Array(id.utf16), Array(name.utf16)))
    }

    public static func run(_ id: String, _ name: String, _ body: () throws -> Void) -> Bool {
        let idUnits = Array(id.utf16)
        let nameUnits = Array(name.utf16)
        Test.currentTestId = idUnits
        let budgetMs = boringTestTimeoutBudgetMs()
        let startedAt = ContinuousClock().now
        // The result line carries its own newline; one append per
        // record keeps one record per line in the results file.
        do {
            try body()
            if boringTestElapsedMs(since: startedAt) >= budgetMs {
                // A body that returned at or past the budget raises the
                // failure type of an assertion, so the clause below records
                // the fail line with the timeout message and the runner
                // reports the test as failed too.
                let text = "this test timed out after " + String(budgetMs) + "ms"
                throw TestFailure(message: Array(text.utf16))
            }
            boringTestAppendResult(TestCore.resultLine(idUnits, nameUnits, false, []))
            Test.currentTestId = []
            return false
        } catch let error as TestFailure {
            boringTestAppendResult(TestCore.resultLine(idUnits, nameUnits, true, error.message))
            Test.currentTestId = []
            return true
        } catch let error as BoringException {
            boringTestAppendResult(TestCore.resultLine(idUnits, nameUnits, true, Array(error.message.utf16)))
            Test.currentTestId = []
            return true
        } catch {
            let fallback = String(describing: error)
            boringTestAppendResult(TestCore.resultLine(idUnits, nameUnits, true, Array(fallback.utf16)))
            Test.currentTestId = []
            return true
        }
    }
}

