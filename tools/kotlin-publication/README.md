# Kotlin publication project

The nine Maven artifacts of the Kotlin tree the boring driver emits are produced
by this Gradle project. The driver runs the publication itself: a Kotlin bundle
that declares `kmpPublication: true` publishes during `pack`, and the project
file carries no command and no path.

## What it publishes

`engine/` declares the root `kotlinMultiplatform` publication and eight targets:
`jvm`, `android`, `macosArm64`, `iosArm64`, `iosSimulatorArm64`, `linuxX64`,
`linuxArm64`, `mingwX64`. The group is `org.tiqian`; the artifactIds are
`tiqian-engine` and `tiqian-engine-<target>`. These coordinates are the
published API names. `build.gradle.kts` sets the POM fields: the publication
name and description, the MPL-2.0 license, the developer entry, and the
source-control links.

## How the driver runs it

The flake installs this directory into the driver package and the `boring`
wrapper exports its path as `BORING_PUBLICATION_PROJECT`. A driver started
without its wrapper resolves, in order, `$BORING_SOURCE/tools/kotlin-publication`
(the source tree the flake exports) and then
`<cwd>/.haxelib/boring/git/tools/kotlin-publication` (the haxelib checkout).
None of these is a sibling checkout: a published driver always finds its own
copy. On `pack`, a bundle with `kmpPublication: true` gets these arguments:

```
gradlew -p <per-run copy> publishToMavenLocal
  -PmavenDir=<outRoot>/<id>/maven
  -PpublicationVersion=<package.version>
  -PkotlinGenDir=<outRoot>/<id>/gen
  -PkotlinGenTestsDir=<outRoot>/<id>/gen-tests
  -PbuildRoot=<outRoot>/<id>/gradle/build
  --project-cache-dir=<outRoot>/<id>/gradle/project-cache
  --no-daemon
```

The installed project is read-only, and Gradle 9 refuses to configure a project
whose root directory cannot be written (it writes `build/reports/problems`
there: `Configuring project ':' without an existing directory is not allowed`).
The driver therefore deletes `<outRoot>/<id>/gradle/project` and copies the
installed project into it on every pack run, and never writes the installed
tree. The source of record stays the copy that ships with the driver, so a flake
pin change installs a new copy. The copy is 10 files and about 75 KB; the
Gradle build and project cache beside it (`<outRoot>/<id>/gradle/build` and
`project-cache`) persist between pack runs on purpose so the second run
reuses the compiled targets.

The wrapper downloads Gradle 9.6.0 (about 140 MB compressed, 152 MB unpacked)
into `GRADLE_USER_HOME` on the first run of a CI job. That download is a
new cost of this project: a job that does not cache `GRADLE_USER_HOME` pays
it once per run.

## Input tree

The Kotlin sources are a driver output. The driver passes absolute `gen` and
`gen-tests` paths derived from the project root, so the build resolves no path
through the process working directory; the defaults below serve a standalone
invocation:

- `reference/kotlin-f32/gen` and `reference/kotlin-f32/gen-tests`, produced by
  `bun run gen:kotlin-f32`;
- `-PkotlinGenDir` and `-PkotlinGenTestsDir` override them. A relative path
  resolves against this project's root, an absolute path is used as written.

This repository's own emission is the codec's JVM-only tree: it carries the codec
host edges, `gen/runtime/Console.kt` calls `System.err` and
`gen/runtime/Process.kt` calls `ProcessBuilder`. The native and Android targets
cannot compile that tree, so the nine-publication run consumes an engine
emission. A bundle that declares `kmpPublication` must therefore be generated
from a Kotlin source set that targets all eight platforms.

## Commands

Publish into a scratch Maven directory:

```shell
./gradlew publishToMavenLocal \
  -PmavenDir=/tmp/boring-maven \
  -PpublicationVersion=1.2.3 \
  -PkotlinGenDir=/path/to/engine-haxe/out/kotlin-f32/gen \
  -PkotlinGenTestsDir=/path/to/engine-haxe/out/kotlin-f32/gen-tests
```

Run the generated test suite through the generated `TestMainKt`:

```shell
./gradlew generatedTestSuite -PpublicationVersion=1.2.3 \
  -PkotlinGenDir=/path/to/engine-haxe/out/kotlin-f32/gen \
  -PkotlinGenTestsDir=/path/to/engine-haxe/out/kotlin-f32/gen-tests
```

## Toolchain and its CI cost

The wrapper lives in this repository and pins Gradle 9.6.0; the first run
downloads the distribution into `GRADLE_USER_HOME`, which CI caches or pays for
once. The flake does not provide Gradle: a nixpkgs Gradle would add roughly
150 MB to every Linux devShell for a tool the wrapper already pins.
The build applies Kotlin Multiplatform 2.3.20 and AGP 9.3.1
(`com.android.kotlin.multiplatform.library`) with `compileSdk = 36` and
`minSdk = 23`, so the Android AAR needs Android SDK platform 36 and
build-tools 36.0.0. The devShell exports `ANDROID_HOME` on Linux from
`androidenv.composeAndroidPackages`; the composition adds about 320 MB to the
Linux devShell (platform 36 146 MB, build-tools 36.0.0 152 MB, platform-tools
37.0.1 22 MB) and no NDK. Kotlin/Native dependencies download on the first run
and honour `KONAN_DATA_DIR` for a writable location.
