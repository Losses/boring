# Finite source admission check

This suite checks the request-specific finite source admission entry
`SourceComparisonAnalysis.admit` over declarations. It is a macro-only check:
the entry reads the declaration phase of one compilation and prints no target
text, so no target class path is on the command line.

## Layout

- `admission/AdmissionCases.hx` holds the authored declarations. Each
  declaration states one discriminator of
  `docs/specs/stdlib/16-dataclass-sorted-keys.md` or of the finite demand
  summary.
- `admission/AdmissionProbe.hx` runs the entry once per discriminator and
  prints one canonical line per case.
- `admission-expected.tsv` holds the expected line per case. The expectations
  are written from the source rule, never from a probe run.
- `admission-probe.hxml` compiles the check with the shared source analysis on
  the class path.
- `run.sh` runs the check under Nix, records the status of each attempt, and
  verifies that the excluded inputs kept their bytes.

## Result line

The columns are the case name and the canonical result:

| Form | Meaning |
| --- | --- |
| `admitted required=[i] unsupplied=[j] visited=n` | The reachable declarations admit the request, `i` lists the demanded parameter slots, `j` lists the demanded slots whose actual is still a binder, and `n` counts the summarized declarations. |
| `rejected stored-field type=T at=D.f chain=[...]` | A stored field type is outside the request domain. |
| `rejected demanded-argument type=T at=D.f chain=[...]` | A demanded actual argument supplies no operation. |
| `rejected parameter-without-evidence slot=i ...` | A demanded parameter has no optional equality evidence. |
| `incomplete reason ...` | A written type did not resolve, so no admission answer exists. |

`at` names the declaration and the stored field that carries the failing form.
`chain` lists the nested declaration edges crossed from the requested
declaration, with `cycle` appended when the walk stopped at a repeated
declaration.

## Running

    nix develop -c bash tests/haxe/comparison-source-admission/run.sh

The run writes `probe.stdout`, `probe.stderr`, `expected.tsv`,
`expected.diff`, and the excluded-input hashes under
`out/comparison-source-admission/run-*`. A nonzero exit status names the
failed attempt.

This suite checks the source boundary only. It establishes no Swift or Tiqian
conformance, and it does not decide the pending payload ordering and equality
question.
