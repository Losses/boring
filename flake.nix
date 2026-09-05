{
  description = "Boring shared-subset development environment (Haxe, Rust, TypeScript, Kotlin, Swift, Dart)";

  inputs = {
    nixpkgs.url = "flake:nixpkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Reflaxe is consumed as a dev haxelib; the pin keeps every machine
    # on the same source of the compilation-target framework.
    reflaxe = {
      url = "github:SomeRanDev/reflaxe/v3.0.0";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, rust-overlay, reflaxe }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ rust-overlay.overlays.default ];
            }
          )
        );
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          # The Rust side uses a pinned overlay toolchain, mirroring the
          # tiqian setup; the shell carries the Kotlin/JVM compiler and JDK 21
          # to build and execute the Kotlin codec tree, and no Android SDK.
          # Swift and Dart compile and run their generated codec trees.
          rustToolchain = pkgs.rust-bin.stable.latest.default;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              haxe
              bun
              nodejs_22
              git
              rustToolchain
              kotlin
              jdk21
              swift
              swiftpm
              dart
            ];
            shellHook = ''
              export HAXELIB_PATH="$PWD/.haxelib"
              mkdir -p "$HAXELIB_PATH"
              haxelib dev reflaxe "${reflaxe}" >/dev/null
              haxelib dev boring "$PWD" >/dev/null
              # A linked Swift binary resolves libswiftCore through its
              # RUNPATH, and libswiftCore loads libdispatch from another
              # store path the binary RUNPATH does not cover; generated
              # test binaries run with this directory on LD_LIBRARY_PATH.
              export BORING_SWIFT_LIBDISPATCH="${pkgs.swift-corelibs-libdispatch}/lib"
            '';
          };
        }
      );
    };
}
