# Kotlin publication project

The nine Maven artifacts of the Kotlin tree the boring driver emits are produced
by this Gradle project. The artifacts were produced by tiqian's own Gradle build
before this project existed, which made tiqian the host of a publication whose
input boring writes. The driver now runs the publication itself: a Kotlin bundle
that declares `kmpPublication: true` publishes during `pack`, and the project
file carries no command and no path.

## What it publishes

`engine/` declares the root `kotlinMultiplatform` publication and eight targets:
`jvm`, `android`, `macosArm64`, `iosArm64`, `iosSimulatorArm64`, `linuxX64`,
`linuxArm64`, `mingwX64`. The group is `org.tiqian`, the artifactIds are
`tiqian-engine` and `tiqian-engine-<target>`, and the POM fields are the values
tiqian's root build script set. The coordinates and the artifactIds are part of
the published API and do not change when the publication host changes.

## How the driver runs it

The flake installs this directory into the driver package and the `boring`
wrapper exports its path as `BORING_PUBLICATION_PROJECT`. On `pack`, a bundle
with `kmpPublication: true` gets these arguments:

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
The driver therefore copies the installed project to `<outRoot>/<id>/gradle/project`
before the run and never writes the installed tree. The source of record stays
the copy that ships with the driver, so a flake pin change replaces it.

## Input tree

The Kotlin sources are a driver output. The driver passes `gen` and
`gen-tests` explicitly; the defaults below serve a standalone invocation:

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
  -PpublicationVersion=0.1.0-alpha08 \
  -PkotlinGenDir=/path/to/engine-haxe/out/kotlin-f32/gen \
  -PkotlinGenTestsDir=/path/to/engine-haxe/out/kotlin-f32/gen-tests
```

Run the generated test suite through the generated `TestMainKt`:

```shell
./gradlew generatedTestSuite -PpublicationVersion=0.1.0-alpha08 \
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
