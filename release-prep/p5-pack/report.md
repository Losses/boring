# P5 boring pack dry run

## Conclusion

The TypeScript pack path works end to end: it produces a valid npm tarball
that installs and imports. The Kotlin pack path is blocked by a generated
code defect in one sample (StaticStateOps), which collides on a JVM setter
signature when kotlinc compiles the whole bundle into a jar. No package was
published during this dry run.

## TypeScript pack

Command: BORING_PACKAGE_TSC=$PWD/node_modules/.bin/tsc boring pack ts

The pack action generated the boring-codec package and emitted the artifact
reference/ts/boring-codec-0.1.0.tgz. The tarball holds 167 files, mostly
compiled JavaScript and declaration pairs under dist/. The manifest carries
name boring-codec, version 0.1.0, license MIT, and an exports map that
resolves boring-codec/boring/Fp32 to dist/boring/Fp32.js.

Local install smoke, run against a fresh project:

    bun add <worktree>/reference/ts/boring-codec-0.1.0.tgz
    import { Fp32 } from "boring-codec/boring/Fp32";  // resolves, typeof function

Both steps succeeded.

## Kotlin pack

Command: boring pack kotlin

The generation step succeeds and writes the Kotlin tree under
reference/kotlin/gen. The kotlinc step then fails:

    reference/kotlin/gen/boring/StaticStateOps.kt: platform declaration clash:
    fun <set-current>(...): Unit and fun setCurrent(value: String): Unit have
    the same JVM signature setCurrent(Ljava/lang/String;)V

The sample declares both a var current property and an explicit setCurrent
function, and the Kotlin target emits both, so they collide under kotlinc.

## Blocking list

1. Kotlin pack fails on the StaticStateOps JVM signature collision. The pack
   action needs the sample fixed or excluded from the packed bundle before
   kotlin pack can complete. The test action is unaffected because it
   compiles one module at a time; the pack action compiles the whole bundle
   into one jar.
