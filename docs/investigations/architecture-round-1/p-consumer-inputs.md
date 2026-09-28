# P: Prepare candidate compiler inputs for Tiqian

## Objective and authority

Prepare a reviewable consumer configuration that selects one complete Boring
compiler checkout. G2 verified a haxelib mapping but missed explicit old backend
and sample classpaths. O revision 2 records those paths for twelve bundles.
This task corrects the preparation. It does not run generation, compilation,
native tests, packaging, or the rejected task I command.

Read the applicable repository instructions, O revision 2, and this complete
brief. The Boring checkout is `boring-wt-architecture`, currently `1da1ab83`,
with executable baseline `e3b8bab39ac2d`. The locked Tiqian worktree is
`architecture-workspaces/tiqian-validation`, fixed at
`8504d230228e8206689a2049bbb84b671c1f079a`. Record full identities and relevant
hashes. The existing Tiqian driver remains the flake's `304ed70c` executable;
compatibility with the candidate compiler is still unproven.

## Allowed files and environment

Author the preparation script and its evidence under the owned Boring
`out/architecture-consumer-inputs/`. In the locked Tiqian worktree, create only
`boring-architecture-candidate.json` at the root and derived HXML/evidence under
`out/architecture-candidate-inputs/`. Refuse to overwrite existing artifacts
without first reporting their identity and ownership. Do not modify tracked
files, `.haxelib/boring/git`, flake pins, goldens, or compiler source. No commits.

Use the pinned environment where needed. Reading effective haxelib mappings
after the usual shell hook and a candidate override is allowed; a compiler or
driver generation command is excluded. A Nix shell hook may rebuild the ignored
class-name list through the existing roots action; record any such setup action
separately. Preserve the actual driver executable and avoid global configuration.

## Transformation rule

Keep the project file at the Tiqian root: the driver derives its working
directory from that file's location. Preserve the original project fields,
bundle identities, tests, comparison policy, precision, source sets, arguments,
package settings, output paths, and after-generation commands. Change only the
roots-file references to the derived HXML files and add verbose compiler module
loading output for the later candidate provenance check.

Keep `outRoot` and `resultsDir` unchanged. `org/tiqian/protocol/CHeader.hx:44`
writes a fixed header path, and its HXML and after-generation command name a
fixed JavaScript path. This owned consumer worktree already supplies isolation;
another output namespace is unnecessary for preparation and would require
more than changing a project property. No compiler outputs are produced here.

Resolve every HXML include used by the twelve bundles. Derived files may flatten
the include structure if they preserve argument order and repeated arguments.
Detect cycles and reject unsupported include syntax explicitly. Replace every
compiler, sample, standard-library shadow, and macro-directory reference to
`.haxelib/boring/git` with the corresponding absolute candidate path. Keep source
class names, macros, defines, target activation, test roots, and ordinary Tiqian
paths otherwise unchanged. Preserve the stock-Haxe `protocol-c` entry.

Retain `-lib boring` with an explicit post-hook candidate haxelib override; the
later launch must assert its effective package path. Keep Reflaxe and the pinned
library dependencies explicit in the record. Do not infer library resolution
from revision markers or a nested `.dev` file. The derived classpaths and the
package mapping must agree on candidate identity.

Use an existing configuration parser or bounded text replacements whose exact
diff can be reviewed. Do not write a new JSON parser. If the current files admit
only a bounded transformation, document that input domain and reject unexpected
forms explicitly.

## Required checks and delivery

Without invoking a compiler, verify all twelve roots, include completeness,
preserved argument order, replacement counts, existence of candidate directories,
unchanged project properties, and unchanged tracked Tiqian content. Record source
and derived hashes and the full transformation diff. A mapping review must find
no live compiler/sample path into the old export. Distinguish this static check
from actual compiler module resolution, which remains pending.

Deliver the script, prepared project and HXML paths, mapping manifest, exact
preparation/check commands and statuses, remaining uncertainties, and the
proposed single `swift-f32` generation command with driver identity, working
directory and post-hook assertions. The proposed command is unexecuted and
requires resolution of task I's automatic-review rejection. Later acceptance
must inspect verbose module-loading records for the shared compiler, Swift
backend, and runtime/sample sources.

Write the report to `/tmp/boring-architecture-round1/reports/p.md`. If a required
source path or transformation cannot be established, stop the dependent
preparation and report the concrete missing fact. Do not repair source semantics
or reduce the twelve-bundle scope to make the check pass.
