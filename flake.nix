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
    nixpkgs-libxml2 = {
      url = "github:NixOS/nixpkgs/nixos-24.05";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, rust-overlay, reflaxe, nixpkgs-libxml2 }:
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

      swiftUrl = "https://download.swift.org/swift-6.2.4-release/amazonlinux2/swift-6.2.4-RELEASE/swift-6.2.4-RELEASE-amazonlinux2.tar.gz";
      swiftHash = "sha256-lpsSQaP9mqRGy0fBsuSnxypU351I7G9lrtCVSQlacfU=";

      mkLinuxSwift =
        pkgs:
        let
          libxml2Old = (import nixpkgs-libxml2 { system = "x86_64-linux"; }).libxml2;
          swiftDist = pkgs.stdenvNoCC.mkDerivation {
            pname = "swift-toolchain";
            version = "6.2.4-al2";
            src = pkgs.fetchurl { url = swiftUrl; hash = swiftHash; };
            dontConfigure = true;
            dontBuild = true;
            dontStrip = true;
            dontFixup = true;
            installPhase = ''
              runHook preInstall
              cp -a . "$out"/
              runHook postInstall
            '';
          };
          fhsEnv = pkgs.buildFHSEnv {
            name = "swift-6.2.4-fhs";
            targetPkgs = pkgs: with pkgs; [
              glibc glibc.dev linuxHeaders libgcc gcc.cc.lib gcc.cc binutils
              coreutils git curl openssl zlib libxml2Old sqlite ncurses libedit
              icu util-linux python3 clang
            ];
            runScript = pkgs.writeShellScript "swift-fhs-dispatch" ''
              exec "$@"
            '';
          };
          wrapSwiftBin =
            name:
            pkgs.writeShellScriptBin name ''
              export LD_LIBRARY_PATH="/usr/lib64:/usr/lib"
              exec "${fhsEnv}/bin/swift-6.2.4-fhs" "${swiftDist}/usr/bin/${name}" "$@"
            '';
        in
        pkgs.symlinkJoin {
          name = "swift-6.2.4-wrapped";
          paths = map wrapSwiftBin [ "swift" "swiftc" "swift-build" "swift-package" "swift-test" "swift-run" ];
          passthru = {
            inherit swiftDist fhsEnv;
            libdispatch = "${swiftDist}/usr/lib/swift/linux";
          };
        };
    in
    {
      packages = forAllSystems (pkgs:
        if pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64 then
          { swift-toolchain = (mkLinuxSwift pkgs).passthru.swiftDist; default = mkLinuxSwift pkgs; }
        else
          { default = pkgs.swift; });
      devShells = forAllSystems (
        pkgs:
        let
          # The Rust side uses a pinned overlay toolchain, mirroring the
          # tiqian setup; the shell carries the Kotlin/JVM compiler and JDK 21
          # to build and execute the Kotlin codec tree, and no Android SDK.
          # Swift and Dart compile and run their generated codec trees.
          rustToolchain = pkgs.rust-bin.stable.latest.default;
          useLinuxSwift = pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64;
          useDarwinSwift = pkgs.stdenv.hostPlatform.isDarwin;
          linuxSwift = mkLinuxSwift pkgs;
          # nixpkgs only carries Swift 5.10 on darwin, below the
          # swift-tools-version:6.0 manifest requirement, so darwin
          # shells use the system Xcode toolchain instead.
          swiftPackages =
            if useLinuxSwift then [ linuxSwift ]
            else if useDarwinSwift then [ ]
            else (with pkgs; [ swift swiftpm ]);
        in
        {
          default = pkgs.mkShell {
            # darwin keeps clang from the system Xcode toolchain as well.
            # stdenv puts its own clang wrapper on PATH regardless of this
            # list, and that wrapper pins an apple-sdk too old for the
            # default Xcode compiler, so the shellHook below exports CC to
            # select the system clang instead; clang stays listed for the
            # non-darwin shells only.
            packages =
              with pkgs; [
                haxe
                bun
                nodejs_22
                git
                rustToolchain
                kotlin
                jdk21
                dart
              ]
              ++ (if useDarwinSwift then [ ] else [ clang ])
              ++ swiftPackages;
            shellHook = ''
              export HAXELIB_PATH="$PWD/.haxelib"
              mkdir -p "$HAXELIB_PATH"
              haxelib dev reflaxe "${reflaxe}" >/dev/null
              haxelib dev boring "$PWD" >/dev/null
              # boring's haxelib.json declares a dependency on "format";
              # install the pinned libraries so fresh checkouts compile.
              # Idempotent: reports "already installed" with exit 0. An
              # offline install fails silently here and surfaces later as
              # the library-specific haxe error.
              haxelib install format 3.8.0 >/dev/null 2>&1 || true
              haxelib install formatter 1.18.0 >/dev/null 2>&1 || true
              # A linked Swift binary resolves libswiftCore through its
              # RUNPATH, and libswiftCore loads libdispatch from another
              # store path the binary RUNPATH does not cover; generated
              # test binaries run with this directory on LD_LIBRARY_PATH.
              ${
                if useLinuxSwift
                then ''export BORING_SWIFT_LIBDISPATCH="${linuxSwift.passthru.libdispatch}"''
                else if useDarwinSwift
                then ''
                  # darwin: Swift comes from the system Xcode toolchain;
                  # LD_LIBRARY_PATH is unused on macOS. SwiftPM reads the
                  # SDKROOT variable first and the CC compiler second, and
                  # the stdenv setup hooks export both: SDKROOT points at
                  # the nixpkgs apple-sdk (built with Swift 5.10) and CC at
                  # the stdenv wrapper. Pin the manifest build to the
                  # system toolchain by overriding both.
                  export CC=/usr/bin/clang
                  if [ -x /usr/bin/xcrun ]; then
                    export SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
                  fi
                ''
                else ''export BORING_SWIFT_LIBDISPATCH="${pkgs.swift-corelibs-libdispatch}/lib"''
              }
            '';
          };
        }
      );
    };
}
