# Feature spec 25: Package artifacts

## Scope

Feature spec 24 made each output tree a loadable package of its
ecosystem. This specification rules the pack step: with one define the
compiler writes the ecosystem's distribution artifact for the tree the
compilation emitted. The formats are the install formats of the native client
tools, because the artifact of a compilation exists to travel through a
registry: an npm `.tgz`, a cargo `.crate`, a Swift `.zip`, and a Pub
`.tar.gz`. A static registry serves exactly these bytes; the generator
of the registry metadata consumes them as release assets.

| Target | Format | File name | Entry layout |
| --- | --- | --- | --- |
| TypeScript | tar + gzip | `<name>-<version>.tgz` | `package/` prefix on every entry |
| Rust | tar + gzip | `<name>-<version>.crate` | no prefix |
| Swift | zip | `<name>-<version>.zip` | no prefix |
| Dart | tar + gzip | `<name>-<version>.tar.gz` | no prefix, `pubspec.yaml` at the root |
| Kotlin | none | the compilation stops | n/a |

The npm file name replaces `/` with `-` (`@scope/name` becomes
`scope-name`), because a file name cannot carry a path separator; the
member prefix stays `package/`. The other lanes pass the package name
through unchanged.

Packing runs inside the compiler process. At the end of generation the
compiler holds every emitted file in memory, so the artifact is a pure
function of one compilation: no second process runs, no toolchain
beyond the compiler is required, and no file the compilation did not
write can enter an archive. The last property is the reason the entry
set comes from the recorded write list and from no directory walk: a
generated tree can carry files the compilation never wrote (test
execution output, stale artifacts of earlier versions), and a walk
would pack them.

## Defines

- `package-artifacts=emit|none`: `none` (the default when the define
  is absent) writes source and manifest only; `emit` writes the
  artifact after the tree. Any other value stops the compilation with
  `package-artifacts accepts emit or none`.
- The identity comes from spec 24: `package-name`, `package-version`,
  and the shell emission those defines control.
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
path packs that list.

- performance: the bytes are already in memory; packing adds
  compression time to the compile, and nothing to any generated
  program. No process spawns, no toolchain beyond Haxe runs.
- ambiguity: the artifact is exactly the set of files one compilation
  wrote; stale or foreign files cannot appear.
- redundancy: one pack implementation per archive format, shared by
  every consumer of the compiler.
- readability: the archive lists the tree a reader can regenerate.

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
| C1 in-compiler pack | in-memory bytes, no extra process | one compilation, one artifact set | one implementation | archive equals the tree |
| C2 pack scripts | one process per pack | directory walks pick up foreign files | per consumer | producer is a second tool |
| C3 generator packs | as C2 | layout drift between generator and tree | second codebase | n/a |

## Ruling

1. **Off by default, one define to enable.** An artifact is release
   output; everyday regeneration writes source and manifest only.
   `package-artifacts=emit` is the whole enable ceremony, and the
   invalid-value and shell-conflict rejections of the Defines section
   guard it.
2. **Entry set equals the recorded main-tree writes.** Every file the
   compilation saves under its output directory is packed; every path
   that escapes the output directory (the `../` paths of the
   test-output trees) is not. `_GeneratedFiles.txt` is written by
   reflaxe after the compiler returns, so it never enters an artifact.
   The manifest is a recorded write and is packed like any other file.
3. **Layouts follow the install formats.** npm installs a tarball whose
   entries sit under `package/`; cargo and Pub install archives with
   the tree at the root (`pubspec.yaml` at the root is Pub's
   requirement); the Swift zip keeps the tree at the root because the
   registry serves it as a source archive. Entries sort by name in
   every format.
4. **Determinism constants.** Tar entries carry mtime 0, mode 0644,
   uid 0, gid 0, and empty owner names; the archive holds regular
   files only, no directory entries. The gzip stream carries MTIME 0,
   XFL 0, and OS 3 (Unix), at compression level 9. Zip entries carry
   the fixed date June 1, 2020, 12:00:00 read through local-time
   fields, so every timezone encodes the same DOS date. Two
   compilations of the same inputs on the same Haxe toolchain produce
   byte-identical artifacts; the deflate stream comes from the
   interpreter's zlib, so the toolchain version bounds the byte
   identity, and the entry set, ordering, and metadata stay identical
   across toolchains.
5. **Artifact location.** The artifact is written to the parent of the
   output directory. The tree keeps exactly the files the compilation
   wrote: an artifact placed inside the tree would enter later
   directory-based tooling (`npm pack` of the tree, `cargo package`)
   as a stale member of the next artifact.
6. **Kotlin rejects the define.** Gradle modules publish through the
   consumer's build, and no artifact format exists for this lane. A
   compilation with `package-artifacts=emit` on the Kotlin target stops
   with `package artifacts are undefined for the Kotlin target: Gradle
   publication belongs to the consumer's build; pass package-artifacts
   none`.
7. **Archive libraries.** The tar writer comes from the `format`
   haxelib (a build-time dependency declared in `haxelib.json`, so
   `haxelib install` of this compiler installs it); the zip writer
   comes from the Haxe standard library (`haxe.zip`); the gzip writer
   is 24 lines in this repository: `haxe.zip.Compress` produces a zlib
   stream, the emitter strips the zlib header and trailer to the raw
   deflate body, and writes the 10-byte gzip header plus the CRC-32
   and ISIZE trailer. No hand-written format exceeds that fragment,
   and the compiler gains one dependency.
8. **Interaction with spec 24.** The artifact carries the manifest, so
   the npm tarball carries the `exports` map and installs as an
   importable package; the cargo crate carries the `autotests`
   setting; the Pub archive carries the SDK floor. A registry that
   serves these artifacts needs no knowledge of the manifest fields.

## Test hooks

- `tests/ts/package-artifacts.test.ts` generates each lane into a
  temp directory and checks: the npm tarball lists its entries under
  `package/` in sorted order with no `_GeneratedFiles.txt` and no
  test-tree entries, installs with the npm CLI from the `.tgz`, and
  runs a consumer that imports through the `exports` map; the cargo
  `.crate` and the Pub `.tar.gz` list their trees at the root with the
  manifest present; the Swift `.zip` lists the same entry set; two
  generations of the same inputs produce byte-identical artifacts on
  every lane; the Kotlin rejection, the invalid-value rejection, and
  the shell-conflict rejection stop the compilation with their
  messages.
- The repository's `examples/*.hxml` keep artifacts off: reference
  trees regenerate without release output, and the tests enable the
  define in their rewritten hxmls.
