# Place contract fixtures

Diagnostic fixtures only. They observe accepted assignment and access forms
on the pinned tools; they assert no source ruling and no compiler contract,
and they change no compiler, specification, or dependency file.

## Reproduction

One invocation allocates one fresh run directory and records every stage in
it. Run from the repository root:

```
nix develop -c bash tests/haxe/place-contract/run.sh
```

The printed run directory under `out/place-contract/runs/` holds, per stage:
`<stage>.argv` (interpreter, cwd, shell-quoted argv), `<stage>.stdout`,
`<stage>.stderr`, and a row in `status.tsv`. `hashes.txt` maps each generated
or native input and output to its digest, so a runtime result traces to the
artifact that produced it. `summary.txt` collects the status table, the
diagnostic checks, and the verdict. Earlier run directories are never
rewritten.

Every Rust case owns `case-<label>/` with its own `rust-gen`, rlib, and
harness. A stage runs only when its producer stage exited zero in the same
attempt; the downstream stages of a failed producer are recorded as
`not-reached` naming that producer.

## Paired design

`place/PlaceObserveStatic.hx` is one authored module. The Haxe JS entry
(`paired.hxml`, main class `place.PlaceStaticMain`) and the Rust generation
(`rust-gen.hxml`) take the same case defines, so each comparison pairs one
Haxe run with one native run of the same case set: `placeR1`, `placeR2`,
`placeR3`, `placeR5`, `placeR5rec`, `placeR6`, or the whole module with no
define. `placeR5rec` is the record form, authored and labelled separately
from the class form `placeR5`.

## Expected non-success outcomes

`place/rejected/*.hx` must fail compilation with the diagnostic named in the
runner, and `place/PlaceReadFault.hx` must print its marker and then fail
inside the authored store. A rejection that compiles, a missing marker, or an
unrelated error is recorded as a harness defect and fails the run.

## Semantic limits

- A runtime difference is an observation under the pinned tools until its
  governing rule is established. The Haxe JS run is one host observation, not
  a source ruling.
- The record case `placeR5rec` lowers to local scalars for a purely local
  record, so it says nothing about record aliasing through a field or a call.
- A crate that does not compile leaves its runtime unreachable; no runtime
  claim is made for those cases.
- The fixtures cover the listed source forms only. Out-of-range element
  access, closure-captured rebinds, and accessor side effects beyond
  `get_items` are outside this set.
- No generated Rust is edited to pass; a blocked case is reported as blocked.
