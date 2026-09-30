# Compiler-byte provenance fixture

Run from the repository root:

```sh
tests/haxe/compiler-bytes-provenance/run.sh
```

The runner invokes the pinned Haxe binary with `-v`; Haxe's own `Parsed
<absolute path>` lines are the load-time observation. It records every parsed
module below `packages/compiler` in `compiler-modules.sha256`, including its
absolute path and SHA-256, and compares the bytes with the expected checkout.
`haxelib path boring` is retained in `haxelib-path-boring.txt` as resolver
context, but is not substituted for the load-time observation. The generated
JS and source map hashes are written to `generated-output.sha256` together with
the compiler-module records, so the output manifest and compiler identity are
from one allocated run directory.

The focused control was run directly (no pipeline):

```text
POSITIVE_RC=0
PASS run=.../out/compiler-bytes-provenance/runs/run-W8V69ksx
```

A byte-altered `/tmp` compiler copy and a separate old `/tmp` compiler copy
were each run with `COMPILER_ROOT=...`; both returned 1. The raw diagnostic was:

```text
FAIL: compiler module identity mismatch: /tmp/compiler-bytes-tampered/packages/compiler/DefaultArgExpander.hx sha256=7e252ace406c69929ad9220d3d95da367c415b16774e3fbaa1f2949e83fb0893 expected=7e252ace406c69929ad9220d3d95da367c415b16774e3fbaa1f2949e83fb0893
```

The same assertion also rejects the old copy because its observed absolute
module paths are outside the expected checkout. The `/tmp` copies and generated
`out/` evidence are deliberately not repository inputs; the durable fixture and
its probe are committed here.
