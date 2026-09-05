// swift-tools-version:5.9
// SwiftPM test chain of the boring repository (stdlib/17 build-chain
// migration). The generated code tree compiles as one library module;
// the two executables (the jsonl test host and the vector verifier)
// import it across the module boundary, which is why every generated
// declaration renders public. The swift-system dependency (pinned to
// the Swift 5 compatible line) backs the std.Fs host helpers of the
// generated files; the f32 lane is a second tree with its own module.
import PackageDescription

let swiftSystem = Target.Dependency.product(name: "SystemPackage", package: "swift-system")

let package = Package(
    name: "boring",
    dependencies: [
        .package(url: "https://github.com/apple/swift-system", exact: "1.6.6")
    ],
    targets: [
        .target(
            name: "Codec",
            dependencies: [swiftSystem],
            path: "reference/swift/gen",
            exclude: ["_GeneratedFiles.txt", "registry/Main.swift"]
        ),
        .executableTarget(
            name: "BoringSwiftTests",
            dependencies: ["Codec", swiftSystem],
            path: "reference/swift/gen-tests"
        ),
        .executableTarget(
            name: "VectorSwiftTests",
            dependencies: ["Codec"],
            path: "tests/swift"
        ),
        .target(
            name: "CodecF32",
            dependencies: [swiftSystem],
            path: "reference/swift-f32/gen",
            exclude: ["_GeneratedFiles.txt"]
        ),
        .executableTarget(
            name: "BoringSwiftTestsF32",
            dependencies: ["CodecF32", swiftSystem],
            path: "reference/swift-f32/gen-tests"
        ),
        .executableTarget(
            name: "VectorSwiftTestsF32",
            dependencies: ["CodecF32"],
            path: "tests/swift-f32"
        ),
        // The stdlib/17 Windows-arm typecheck probe: the canImport
        // (MSVCRT) and canImport(WinSDK) arm bodies compile on Linux
        // against stub declarations (see its main.swift header).
        .executableTarget(
            name: "WindowsProbeSwiftTests",
            dependencies: [],
            path: "tests/swift-windows-probe"
        ),
    ]
)
