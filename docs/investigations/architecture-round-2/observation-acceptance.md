# A and C observation fixture acceptance

## Accepted delivery

The coordinator accepts the two focused observation fixtures for integration.
This acceptance covers reproducible observations and their declared stages.
Compiler repairs, source-language rulings, target equivalence, and the final
Boring and Tiqian regression remain open.

GLM authored the initial fixtures. Goose reviewed and repaired the classifier
fixture. GLM repaired the place runner against coordinator review. The
coordinator inspected the delivered source, checked retained output and input
hashes, and copied the handed-over files without implementation edits.
Both worker checkouts used `e45c74b7`; their compiler files retain the unfinished
Swift checkpoint described in the round index.

## Evidence reviewed

| Fixture | Final retained run in its worker checkout | Result and limit |
| --- | --- | --- |
| `tests/haxe/classifier-contract` | `out/classifier-contract/run-20260928-042332-rIcP9W` | Source-type probe and ordinary Haxe compile both exit 0. The independent label list has 57 entries: 25 cases and 32 comparator observations. No Boring target generation is established. |
| `tests/haxe/place-contract` | `out/place-contract/runs/place-HncKKQ` | All 48 expected stages have distinct records. Four downstream stages are marked unreached after Rust compile failures. The runner records observations; exit 0 does not mean target equivalence. |

The coordinator independently verified 15 classifier input hashes, 14 place
identity hashes, and 55 place input/output hash records. The final place stage
IDs equal the independent expected set. Both scoped documentation-style checks
exit 0 with no hits. Evidence directories remain local ignored output; the
committed runners reproduce the observations in fresh directories.

The classifier's two captured helper exceptions concern a synthetic macro lazy
input. They are separate from source acceptance and from failed process
attempts. The first repaired runner attempt failed because the fixture used
`Map.length` and `Std.trace`; its files remain alongside the later passing runs.

The place pairs use matching authored source and case defines:

| Case | Haxe JS observation | Rust observation |
| --- | --- | --- |
| R1: RHS replaces the field array | Replacement value 90; original element 17 | Replacement value 97; original element 10 |
| R2: RHS replaces an intermediate object | Replacement value 70; original element 15 | Replacement value 75; original element 10 |
| R3: element store through getter | Stored element 13 | Stored element 10 |
| R5: class intermediates | Values 5, 2, 5 | E0507 at native compilation; runtime unreached |
| R5rec: local record intermediates | Values 5, 2, 5 | Values 5, 2, 5 |
| R6: mutation through a final field | Length 3 | Length 3 |

R5rec's local record scalarizes. Its matching results provide no general record
aliasing guarantee. R1 through R3 establish a target disagreement at this
checkpoint; selecting the repair still requires the source rule and tracing
of evaluation, storage, and writeback decisions.

Four negative source cases match their expected diagnostics. A deliberate null
read reaches its authored marker before failing. The runner's negative checks
also show failure propagation for input-hash capture and artifact hashes; the
exact stage-membership check covers an unexpected prefix ID, a duplicate, and
a missing stage. These are checks of evidence reliability.

## Retained gaps and guidance changes

Earlier versions of both runners overwrote fixed log paths. Those attempts
cannot be reconstructed. The new runners preserve subsequent attempts with
exclusive directory allocation and separate process streams. Retaining a
caught helper exception never repairs the missing history of a failed process.

Review also found shell pipelines that printed a success label after an
unchecked hash or process failure. A report must cite the underlying status;
its summary text cannot establish that status. The coordinator checked actual
hash results independently and stopped an unchecked success-printing command.

Formatting was not an acceptance gate for this fixture batch. The Goose report
checked for an executable named `hxformat` and found none. The environment
lists `formatter` 1.18.0; executable discovery alone cannot establish that no
formatting tool is available.

The next work consumes these fixtures as evidence. Source-container analysis
proceeds in A2. Place design must retain the original evaluated receiver and
index through an effectful RHS and establish writeback to the intended storage.
The contracts distinguish that logical place from a target physical address.
