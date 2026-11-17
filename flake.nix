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
    swift-system = {
      url = "github:apple/swift-system/0b30161977799fd949f7f6848586b82ff6764f73";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, rust-overlay, reflaxe, nixpkgs-libxml2, swift-system }:
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
              # The Kotlin publication project (tools/kotlin-publication/) builds an
              # Android AAR, so the Android SDK's license has to be accepted for
              # the devShell composition below. android-sdk-cmdline-tools is an
              # unfree package, hence allowUnfree.
              config = {
                allowUnfree = true;
                android_sdk.accept_license = true;
              };
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
      mkSwiftSystem =
        pkgs:
        let
          useLinuxSwift = pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64;
          swiftToolchain = if useLinuxSwift then mkLinuxSwift pkgs else pkgs.swift;
          swiftCommand = if pkgs.stdenv.hostPlatform.isDarwin then "/usr/bin/swift" else "${swiftToolchain}/bin/swift";
          swiftcCommand = if pkgs.stdenv.hostPlatform.isDarwin then "/usr/bin/swiftc" else "${swiftToolchain}/bin/swiftc";
          librarySuffix = if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so";
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "boring-swift-system";
          version = "1.6.6";
          src = swift-system;
          nativeBuildInputs = [ pkgs.clang ] ++ (if pkgs.stdenv.hostPlatform.isDarwin then [ ] else [ swiftToolchain ]);
          dontConfigure = true;
          # SPM builds the Package.swift manifest in its own macOS sandbox, and the
          # Nix build sandbox refuses sandbox_apply ("sandbox-exec:
          # sandbox_apply: Operation not permitted"), which failed every macos
          # job. nixpkgs patches swiftpm to skip the nested sandbox whenever
          # NIX_BUILD_TOP is set for the same reason: the Nix sandbox is the real
          # isolation boundary, and the nested one cannot apply inside it.
          # /usr/bin/swift is the unpatched Xcode toolchain, so pass the flag
          # explicitly on Darwin only.
          buildPhase = ''
            runHook preBuild
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            ${if pkgs.stdenv.hostPlatform.isDarwin then "unset DEVELOPER_DIR; export CC=/usr/bin/clang; export SDKROOT=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" else ""}
            ${swiftCommand} build --package-path . --build-path "$TMPDIR/swift-system-build" --target SystemPackage${if pkgs.stdenv.hostPlatform.isDarwin then " --disable-sandbox" else ""}
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            cp -R Sources/CSystem/include/. "$out/"
            module=$(find "$TMPDIR/swift-system-build" -name SystemPackage.swiftmodule -print -quit)
            if [ -z "$module" ]; then
              echo "swift-system: SystemPackage.swiftmodule was not built" >&2
              exit 1
            fi
            cp "$module" "$out/SystemPackage.swiftmodule"
            buildDir="$(dirname "$(dirname "$module")")"
            ${swiftcCommand} -emit-library "$buildDir"/SystemPackage.build/*.o "$buildDir"/CSystem.build/*.o -o "$out/libSystemPackage.${librarySuffix}"
            runHook postInstall
          '';
        };
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          # The driver compiles against the dev haxelib views ("reflaxe",
          # "boring") and the pinned libraries the checkout declares
          # ("format", plus the "formatter" reflaxe depends on). A Nix build
          # has neither the devShell shellHook nor a populated user haxelib
          # repo, and the Linux build sandbox has no network, so the pinned
          # library archives are fetched as fixed-output derivations and
          # registered with "haxelib dev"; the build sandbox has no network
          # for "haxelib install". Without this setup the derivation only ever
          # resolved as a store cache hit; the first rebuild after a source
          # change stopped at haxelib's first-run setup prompt.
          haxelibFormat = pkgs.fetchurl {
            url = "https://lib.haxe.org/files/3.0/format-3,8,0.zip";
            hash = "sha256-6jpnJe5wfVSWVVDVMxyLHqtcVIw1s2gGIvsP+hW1Cf0=";
          };
          haxelibFormatter = pkgs.fetchurl {
            url = "https://lib.haxe.org/files/3.0/formatter-1,18,0.zip";
            hash = "sha256-LSnJtW5UsmQ+B+5kADw/wwpbwTO9y0zBXEjwms2noEc=";
          };
          driver = pkgs.stdenvNoCC.mkDerivation {
            pname = "boring-driver";
            version = "0.0.1";
            src = self;
            nativeBuildInputs = [ pkgs.haxe pkgs.makeWrapper pkgs.unzip ];
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              export HAXELIB_PATH="$TMPDIR/.haxelib"
              export HOME="$TMPDIR/home"
              mkdir -p "$HAXELIB_PATH" "$HOME"
              haxelib setup "$HAXELIB_PATH"
              haxelib dev reflaxe "${reflaxe}" >/dev/null
              # Point "boring" at the unpacked writable source root, not
              # "$src": the compiler's ledger macro resolves the repository
              # root through the class path and writes "$root/out", which the
              # read-only store path cannot accept.
              haxelib dev boring "$PWD" >/dev/null
              mkdir -p "$TMPDIR/libs/format" "$TMPDIR/libs/formatter"
              unzip -q "${haxelibFormat}" -d "$TMPDIR/libs/format"
              unzip -q "${haxelibFormatter}" -d "$TMPDIR/libs/formatter"
              haxelib dev format "$(dirname "$(find "$TMPDIR/libs/format" -name haxelib.json -print -quit)")" >/dev/null
              haxelib dev formatter "$(dirname "$(find "$TMPDIR/libs/formatter" -name haxelib.json -print -quit)")" >/dev/null
              mkdir -p out/driver
              haxe packages/driver/driver.hxml
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin" "$out/share/boring"
              cp out/driver/driver.js "$out/share/boring/driver.js"
              # The Kotlin publication project ships with the driver: the
              # driver's kmpPublication step runs it from this read-only store
              # copy and redirects build and project-cache output elsewhere.
              cp -a tools/kotlin-publication "$out/share/boring/kotlin-publication"
              makeWrapper "${pkgs.bun}/bin/bun" "$out/bin/boring" \
                --add-flags "$out/share/boring/driver.js" \
                --set BORING_PUBLICATION_PROJECT "$out/share/boring/kotlin-publication"
              runHook postInstall
            '';
          };
        in
        {
          inherit driver;
          swift-system = mkSwiftSystem pkgs;
          default =
            if pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64
            then mkLinuxSwift pkgs
            else pkgs.swift;
        }
        // (if pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64 then
          {
            swift-toolchain = (mkLinuxSwift pkgs).passthru.swiftDist;
            linux-swift = mkLinuxSwift pkgs;
          }
        else
          { })
      );
      apps = forAllSystems (pkgs: {
        boring = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.driver}/bin/boring";
        };
        default = self.apps.${pkgs.stdenv.hostPlatform.system}.boring;
      });
      devShells = forAllSystems (
        pkgs:
        let
          # The Rust side uses a pinned overlay toolchain, mirroring the
          # tiqian setup; the shell carries the Kotlin/JVM compiler and JDK 21
          # to build and execute the Kotlin codec tree, and no Android SDK.
          # Swift and Dart compile and run their generated codec trees.
          rustToolchain = pkgs.rust-bin.stable.latest.default;
          # The Kotlin publication project declares
          # com.android.kotlin.multiplatform.library with compileSdk 36, so a
          # Linux shell that runs it needs the platform and build-tools AGP
          # compiles against. No NDK: the generated Kotlin tree carries no native
          # code, and the NDK closure is 2.4G of unrelated build inputs.
          androidComposition = pkgs.androidenv.composeAndroidPackages {
            platformVersions = [ "36" ];
            buildToolsVersions = [ "36.0.0" ];
            includeEmulator = false;
            includeSystemImages = false;
            includeNDK = false;
            includeSources = false;
          };
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
            # AGP resolves the Android platform and build-tools through
            # ANDROID_HOME. Linux only: the darwin shells keep the 320M closure
            # out of their environment until a darwin publication path exists.
            ANDROID_HOME = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux
              "${androidComposition.androidsdk}/libexec/android-sdk";
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
                self.packages.${pkgs.stdenv.hostPlatform.system}.driver
                self.packages.${pkgs.stdenv.hostPlatform.system}.swift-system
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
              # SwiftPM writes its user-level cache under Foundation's home
              # directory. A sandboxed home is read-only, so point
              # Foundation at a writable scratch dir; otherwise every
              # swift build prints two "not accessible or not writable"
              # warnings that the warning gate counts.
              export CFFIXED_USER_HOME="$PWD/.scratch/swiftpm-home"
              mkdir -p "$CFFIXED_USER_HOME"
              export XDG_CACHE_HOME="$CFFIXED_USER_HOME/.cache"
              mkdir -p "$XDG_CACHE_HOME"
              haxelib dev reflaxe "${reflaxe}" >/dev/null
              if [ -f "$PWD/haxelib.json" ] && [ -d "$PWD/packages/compiler" ]; then
                boring_source="$PWD"
              else
                boring_source="${self.outPath}"
              fi
              haxelib dev boring "$boring_source" >/dev/null
              export BORING_SWIFT_SYSTEM_PACKAGE="${self.packages.${pkgs.stdenv.hostPlatform.system}.swift-system}"
              # boring's haxelib.json declares a dependency on "format";
              # install the pinned library versions so fresh checkouts compile.
              if [ ! -d "$HAXELIB_PATH/format/3,8,0" ] && ! haxelib install format 3.8.0 >/dev/null; then
                echo "boring devShell: failed to install haxelib format 3.8.0" >&2
                exit 1
              fi
              if [ ! -d "$HAXELIB_PATH/formatter/1,18,0" ] && ! haxelib install formatter 1.18.0 >/dev/null; then
                echo "boring devShell: failed to install haxelib formatter 1.18.0" >&2
                exit 1
              fi
              # A linked Swift binary resolves libswiftCore through its
              # RUNPATH, and libswiftCore loads libdispatch from another
              # store path the binary RUNPATH does not cover; generated
              # test binaries run with this directory on LD_LIBRARY_PATH.
              ${
                if useLinuxSwift
                then ''
                  # The pinned loader below skips the host's default library
                  # directories, and libstdc++ is a transitive dependency of
                  # the swift libraries (the executable RUNPATH does not
                  # cover transitive lookups), so the gcc lib directory rides
                  # along on the shared LD_LIBRARY_PATH prefix.
                  export BORING_SWIFT_LIBDISPATCH="${linuxSwift.passthru.libdispatch}:${pkgs.gcc.cc.lib}/lib"
                  # The FHS toolchain records a generic /lib64 interpreter
                  # while its RUNPATH resolves libc to this glibc, so a host
                  # with an older system loader (ubuntu-24.04 runners carry
                  # 2.39) runs a 2.39 loader against the 2.42 libc and the
                  # process crashes before main. Test binaries pin the
                  # interpreter to the matching loader through this path.
                  export BORING_SWIFT_DYNAMIC_LINKER="${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
                ''
                else if useDarwinSwift
                then ''
                  # darwin: Swift comes from the system Xcode toolchain;
                  # LD_LIBRARY_PATH is unused on macOS. The stdenv setup
                  # hooks export CC at the stdenv wrapper and SDKROOT and
                  # DEVELOPER_DIR at the nixpkgs apple-sdk (built with
                  # Swift 5.10); SwiftPM reads SDKROOT first, and
                  # DEVELOPER_DIR redirects xcrun itself, so it must be
                  # cleared before asking xcrun for the system SDK path.
                  unset DEVELOPER_DIR
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
