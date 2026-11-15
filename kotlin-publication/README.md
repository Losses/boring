# Kotlin publication project

The nine Maven artifacts of the Kotlin tree the boring driver emits (bundle
`kotlin-f32`) are produced by this Gradle project. The artifacts were produced by
tiqian's own Gradle build before this project existed, which made tiqian the host
of a publication whose input boring writes.

## What it publishes

`engine/` declares the root `kotlinMultiplatform` publication and eight targets:
`jvm`, `android`, `macosArm64`, `iosArm64`, `iosSimulatorArm64`, `linuxX64`,
`linuxArm64`, `mingwX64`. The group is `org.tiqian`, the artifactIds are
`tiqian-engine` and `tiqian-engine-<target>`, and the POM fields are the values
tiqian's root build script set. The coordinates and the artifactIds are part of
the published API and do not change when the publication host changes.

## Input tree

The Kotlin sources are a driver output. The default is this repository's own
kotlin-f32 emission, `reference/kotlin-f32/gen` and
`reference/kotlin-f32/gen-tests`, produced by `bun run gen:kotlin-f32`.
`-PkotlinGenDir` and `-PkotlinGenTestsDir` point the build at another emission;
a relative path resolves against this project's root, an absolute path is used
as written.

This repository's own emission is the codec's JVM-only tree: it carries the codec
host edges, `gen/runtime/Console.kt` calls `System.err` and
`gen/runtime/Process.kt` calls `ProcessBuilder`. The native and Android targets
cannot compile that tree, so the nine-publication run consumes the engine
emission the driver produces from tiqian's `engine-haxe` sources.

## Commands

Generate this repository's tree:

```shell
bun run gen:kotlin-f32
```

Publish into a scratch Maven directory:

```shell
./gradlew publishToMavenLocal \
  -Dmaven.repo.local=/tmp/boring-maven \
  -PtiqianVersion=0.1.0-alpha08 \
  -PkotlinGenDir=/path/to/engine-haxe/out/kotlin-f32/gen \
  -PkotlinGenTestsDir=/path/to/engine-haxe/out/kotlin-f32/gen-tests
```

Run the generated test suite through the generated `TestMainKt`:

```shell
./gradlew generatedTestSuite -PtiqianVersion=0.1.0-alpha08 \
  -PkotlinGenDir=/path/to/engine-haxe/out/kotlin-f32/gen \
  -PkotlinGenTestsDir=/path/to/engine-haxe/out/kotlin-f32/gen-tests
```

## Toolchain

The wrapper pins Gradle 9.6.0. The build applies Kotlin Multiplatform 2.3.20 and
AGP 9.3.1 (`com.android.kotlin.multiplatform.library`) with `compileSdk = 36`
and `minSdk = 23`, so the Android AAR needs Android SDK platform 36 and
build-tools 36.0.0. The devShell exports `ANDROID_HOME` on Linux from
`androidenv.composeAndroidPackages`; the composition adds about 320 MB to the
Linux devShell (platform 36 146 MB, build-tools 36.0.0 152 MB, platform-tools
37.0.1 22 MB) and no NDK. Kotlin/Native dependencies download on the first run
and honour `KONAN_DATA_DIR` for a writable location.
