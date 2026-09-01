# Feature spec 25: Package artifacts

## Scope

Feature spec 24 made each output tree a loadable package of its
ecosystem. This specification rules the pack step: with one define the
compiler writes the ecosystem's distribution artifact for the tree the
compilation emitted. Every artifact is the install unit its registry
distributes. The cargo `.crate`, the Pub `.tar.gz`, and the Swift
`.zip` carry source, because those registries install source and their
client tools compile on the consumer side. The npm `.tgz` and the
Kotlin target carry build output, because npm installs JavaScript a
plain `node` process can load and the JVM installs jars: for those two
ecosystems a source archive would be an install that cannot run. The
two compiled targets therefore run the host's compiler at pack time,
through a define that names the executable.

| Target | Format | File name | Entry layout |
| --- | --- | --- | --- |
| TypeScript | tar + gzip | `<name>-<version>.tgz` | `package/` prefix; `package.json` plus `dist/` with `.js` and `.d.ts` |
| Rust | tar + gzip | `<name>-<version>.crate` | no prefix |
| Swift | zip | `<name>-<version>.zip` | no prefix |
| Dart | tar + gzip | `<name>-<version>.tar.gz` | no prefix, `pubspec.yaml` at the root |
| Kotlin | Maven directory | `maven/<groupId path>/<name>/<version>/<name>-<version>.{jar,pom}` | jar plus pom plus their `.sha1` files |

The npm file name replaces `/` with `-` (`@scope/name` becomes
`scope-name`), because a file name cannot carry a path separator; the
member prefix stays `package/`. The other targets pass the package name
through unchanged.

Packing runs inside the compiler process. At the end of generation the
compiler holds every emitted file in memory, so the artifact is a pure
function of one compilation plus, on the compiled targets, one host tool
invocation. The source targets spawn nothing: no toolchain beyond Haxe
runs. The compiled targets spawn exactly the compiler of their
ecosystem (`package-tsc`, `package-kotlinc`); a missing define or a
failing tool stops the compilation with the tool's own exit code and
output. In every target the entry set derives from the recorded write
list and from no directory walk of the output tree: a generated tree
can carry files the compilation never wrote (test execution output,
stale artifacts of earlier versions), and a walk would pack them.

## Defines

- `package-artifacts=emit|none`: `none` (the default when the define
  is absent) writes source and manifest only; `emit` writes the
  artifact after the tree. Any other value stops the compilation with
  `package-artifacts accepts emit or none`.
- The identity comes from spec 24: `package-name`, `package-version`,
  and the shell emission those defines control.
- `package-tsc=<executable>`: the TypeScript compiler that builds the
  npm artifact. A compilation with `package-artifacts=emit` on the
  TypeScript target and no `package-tsc` stops with `package artifacts
  on the TypeScript target require the TypeScript compiler: the npm
  artifact ships compiled JavaScript and declarations; pass
  package-tsc <executable> or package-artifacts none`.
- `package-kotlinc=<executable>`: the Kotlin compiler that builds the
  jar of the Maven directory. The equivalent missing-define rejection
  names `package-kotlinc`.
- `package-group=<groupId>`: the Maven groupId of the Kotlin artifact,
  written as the pom `groupId` and as the directory path under
  `maven/` with `.` separators replaced by `/`. The default is the
  package name.
- `package-artifacts=emit` requires `package-shell=emit`: the artifact
  wraps the manifest, and a manifest the tree does not carry would
  make the artifact uninstallable. A compilation combining
  `package-artifacts=emit` with `package-shell=none` stops with
  `package artifacts require the package shell: an artifact wraps the
  manifest the shell emits; pass package-shell emit or package-artifacts
  none`.

## Candidate translations

### Candidate 1: Pack inside the compiler (recorded writes only)

The compiler records every main-tree write it performs, and the emit
path packs that list; the compiled targets additionally run the host
compiler the defines name.

- performance: the source targets pack in-memory bytes; the compiled
  targets add one host compiler invocation to the compile, and nothing
  to any generated program.
- ambiguity: the artifact derives from exactly the set of files one
  compilation wrote; stale or foreign files cannot appear.
- redundancy: one pack implementation per archive format, shared by
  every consumer of the compiler.
- readability: the archive lists what a reader can regenerate.

### Candidate 2: Ship pack scripts the consumer runs

The repository provides a script per ecosystem that runs `npm pack`,
`cargo package`, or the equivalent client command over the tree.

- performance: one extra process per pack, each carrying its own
  toolchain requirement.
- ambiguity: each client tool re-walks the directory, so the artifact
  contains whatever the tree happens to hold, including files the
  compilation did not write.
- redundancy: the script set repeats per consumer; the compiler carries
  no pack implementation of its own.
- readability: the artifact is readable, but its producer is a second
  tool the reader must find and trust.

### Candidate 3: No packing in this repository

The registry generator packs from release checkouts.

- performance: as Candidate 2, moved into the generator.
- ambiguity: the generator re-derives the layout per ecosystem, and
  its derivation can drift from the tree the compiler emits.
- redundancy: layout knowledge lives in a second codebase.
- readability: n/a.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 in-compiler pack | in-memory bytes; one host tool on the compiled targets | one compilation, one artifact set | one implementation | archive equals the tree or its compile |
| C2 pack scripts | one process per pack | directory walks pick up foreign files | per consumer | producer is a second tool |
| C3 generator packs | as C2 | layout drift between generator and tree | second codebase | n/a |

## Ruling

1. **Off by default, one define to enable.** An artifact is release
   output; everyday regeneration writes source and manifest only.
   `package-artifacts=emit` is the whole enable ceremony, and the
   invalid-value and shell-conflict rejections of the Defines section
   guard it.
2. **The recorded main-tree writes are the pack input.** Every file
   the compilation saves under its output directory enters the pack
   input; every path that escapes the output directory (the `../`
   paths of the test-output trees) does not. `_GeneratedFiles.txt` is
   written by reflaxe after the compiler returns, so it never enters
   an artifact. On the source targets (cargo, Pub, Swift) the recorded
   writes are also the archive entries. On the compiled targets the
   entry set is the output of the host compiler over that input: the
   npm tarball carries `dist/` plus the artifact manifest, and the
   Kotlin jar carries the kotlinc classes. Two recorded files stay out
   of the compile inputs by rule: a manifest the shell emitted
   (`package.json` on npm, `build.gradle.kts` on Kotlin) is not
   source, and the runtime test entry (`runtime/test.ts`) imports
   node:fs for the repository's test harness and has no role in an
   installed package.
3. **Layouts follow the install formats.** npm installs a tarball whose
   entries sit under `package/`; cargo and Pub install archives with
   the tree at the root (`pubspec.yaml` at the root is Pub's
   requirement); the Swift zip keeps the tree at the root because the
   registry serves it as a source archive; Gradle and Maven resolve
   files from a repository directory, so the Kotlin target writes
   `maven/<groupId path>/<name>/<version>/` with the jar, the pom, and
   their sha1 checksums. Entries sort by name in every format.
4. **Determinism constants, scoped per target.** Tar entries carry mtime
   0, mode 0644, uid 0, gid 0, and empty owner names; the archive
   holds regular files only, no directory entries. The gzip stream
   carries MTIME 0, XFL 0, and OS 3 (Unix), at compression level 9.
   Zip entries carry the fixed date June 1, 2020, 12:00:00 read
   through local-time fields, so every timezone encodes the same DOS
   date; the jar holds the same constant, which normalizes the
   timestamps kotlinc bakes into its own archives. On the source targets
   two compilations of the same inputs on the same Haxe toolchain
   produce byte-identical artifacts. On npm the byte identity of the
   `.js` and `.d.ts` members additionally requires the same `tsc`; on
   Kotlin the jar bytes additionally require the same `kotlinc` and
   the same JDK. The manifest bytes, the entry sets, the ordering, and
   the metadata constants hold across toolchains.
5. **Artifact location.** The artifact is written to the parent of the
   output directory. The tree keeps exactly the files the compilation
   wrote: an artifact placed inside the tree would enter later
   directory-based tooling (`npm pack` of the tree, `cargo package`)
   as a stale member of the next artifact. The Maven directory and the
   pack-time staging trees (`.package-npm-stage`, removed after the
   pack) sit beside the tree for the same reason.
6. **Kotlin packs a Maven repository directory.** The JVM ecosystem
   resolves artifacts from Maven-layout directories, so this target
   writes the repository layout itself: the
   groupId comes from `package-group` (defaulting to the package
   name), the artifactId and version from the spec 24 identity, and
   the directory holds `<name>-<version>.jar`, `<name>-<version>.pom`,
   and the matching `.sha1` checksum files (forty lowercase hex
   digits, the sha1 of exactly the saved bytes). The jar repacks the
   kotlinc class output through this feature's fixed-date zip writer.
   The pom is compiler-written: the spec 24 identity plus a
   `kotlin-stdlib` dependency pinned to the plugin version the spec 24
   build manifest states, because the jar carries module classes only
   and the stdlib arrives as a declared dependency. `maven-metadata.xml`
   lists versions across releases, so it belongs to the registry
   generator together with every other registry-wide field.
7. **The npm artifact is compiled.** The pack step stages the recorded
   `.ts` writes with their import specifiers rewritten from `.ts` to
   `.js` (artifact mode holds only relative specifiers, because the
   spec 24 shell rejects a by-name runtime import), compiles the stage
   with `tsc -p` under a fixed configuration (`module nodenext`,
   `target es2022`, `declaration`, `outDir dist`, `rootDir .`,
   `skipLibCheck`), and packs `dist/` plus an artifact manifest. That
   manifest retargets the spec 24 exports map at `./dist/*.js` with a
   `types` condition on `./dist/*.d.ts`, drops `private` (the tarball
   exists to travel through a registry), and drops the typescript
   devDependency (the artifact carries declarations, so consumers
   never typecheck it). The tree's own manifest keeps serving the
   source consumers of spec 24; the two manifests state different
   truths for different readers.
8. **Host tools fail loudly.** The compiled targets run their tool with
   the full command line, read the complete output, and on a nonzero
   exit stop the compilation through an error that carries the exit
   code, the command line, and the output. A pack step never guesses
   around a failing compiler, and a missing define names the define
   that supplies the executable.
9. **Archive libraries.** The tar writer comes from the `format`
   haxelib (a build-time dependency declared in `haxelib.json`, so
   `haxelib install` of this compiler installs it); the zip writer
   comes from the Haxe standard library (`haxe.zip`); the gzip writer
   is 24 lines in this repository: `haxe.zip.Compress` produces a zlib
   stream, the emitter strips the zlib header and trailer to the raw
   deflate body, and writes the 10-byte gzip header plus the CRC-32
   and ISIZE trailer. No hand-written format exceeds that fragment,
   and the compiler gains one dependency.
10. **Interaction with spec 24.** Every artifact carries the identity
    the shell defines. The npm tarball carries the retargeted exports
    map and installs as an importable package; the cargo crate carries
    the `autotests` setting; the Pub archive carries the SDK floor;
    the Kotlin directory carries the pom beside the jar. A registry
    that serves these artifacts needs no knowledge of the manifest
    fields beyond parsing the Maven layout it already serves.

## Test hooks

- `tests/ts/package-artifacts.test.ts` generates each target into a
  temp directory and checks: the npm tarball lists `package/dist/`
  with `.js` and `.d.ts` members in sorted order, no TypeScript
  source, and no `_GeneratedFiles.txt` or test-tree entries, installs
  with the npm CLI from the `.tgz`, and runs a consumer under plain
  `node` through the retargeted `exports` map; the cargo `.crate` and
  the Pub `.tar.gz` list their trees at the root with the manifest
  present; the Swift `.zip` lists the same entry set; the Kotlin target
  writes the Maven directory with the pom fields, sha1 checksums that
  match the saved bytes, and a jar whose entries sort and carry the
  fixed zip date; two generations of the same inputs produce
  byte-identical artifacts on every target; the invalid-value rejection
  and the shell-conflict rejection stop the compilation with their
  messages; the missing `package-tsc` and `package-kotlinc` rejections
  stop the compilation with their messages; a `package-tsc` and a
  `package-kotlinc` that exit nonzero forward the exit code and the
  command line into the compilation error.
- The repository's `examples/*.hxml` keep artifacts off: reference
  trees regenerate without release output, and the tests enable the
  define in their rewritten hxmls.
