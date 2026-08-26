{
  description = "Boring shared-subset development environment (Haxe, Rust, TypeScript)";

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
          # tiqian setup; the shell carries no JDK and no Android SDK.
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
            ];
            shellHook = ''
              export HAXELIB_PATH="$PWD/.haxelib"
              mkdir -p "$HAXELIB_PATH"
              haxelib dev reflaxe "${reflaxe}" >/dev/null
            '';
          };
        }
      );
    };
}
