# Driver revision provenance verifier

`verify-driver-revision.sh` checks that a pinned nix `boring-driver` artifact is
reproducible from the Boring source revision that a consuming flake lock names.

## Why this exists (P09 B2)

The P09 B2 audit could not bind the pinned driver artifact
(`share/boring/driver.js`, sha256 `a8f5ef0e...`) to a git revision: the nix
store source tree carries no `.git` and the derivation is `unknown-deriver`, so
the store path alone proves nothing about a revision.

The missing link is the flake lock. A `github:` flake input is content-addressed
by its `narHash`; `nix hash path` on the source tree the driver derivation
builds from reproduces that `narHash` byte for byte, which binds the tree to the
locked revision. Rebuilding the driver from that tree and matching the recorded
`driver.js` sha256 completes the chain.

## Usage

```sh
nix develop <boring-repo> -c tools/driver-provenance/verify-driver-revision.sh \
  --flake-lock /path/to/tiqian/flake.lock \
  --source /nix/store/<hash>-source \
  --expected-driver-sha256 <sha256> \
  [--expected-rev <40-hex>] \
  [--artifact /nix/store/<hash>-boring-driver-0.0.1/share/boring/driver.js] \
  [--workdir <dir>] [--rm]
```

The script must run under `nix develop` of the Boring repo (haxe 4.3.7 on
PATH); it also needs `nix`, `python3` and `sha256sum`.

## What a PASS establishes

A PASS establishes the four links the script prints:

1. the flake lock's `boring` input records the same revision in `locked` and
   `original`;
2. `nix hash path <source>` equals the lock's `narHash`, so the source tree is
   the locked revision;
3. `haxe packages/driver/driver.hxml` exits 0 in a private copy of that tree
   (argv, cwd, rc and both stream sizes are printed);
4. the rebuilt `out/driver/driver.js` sha256 equals the recorded pinned hash,
   and, with `--artifact`, is byte-identical to the installed artifact.

## What a PASS does not establish

It does not cover generation, tests, or driver behaviour, and it does not
decide which driver a consumer should run. It is not a substitute for the
fixed-matrix acceptance. The P09 B2 run of 2026-10-05 and its raw logs are
archived in the workspace evidence archive, not in this repository.
