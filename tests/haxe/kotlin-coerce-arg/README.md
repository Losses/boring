# Kotlin Argument coercion fixture

P2.4. An argument whose callee parameter does not admit absence (a non-null
Kotlin parameter) extracts the value, so a nullable argument hardens with !!:

* StringTools.trim(s) where s is Null<String> -- the receiver s renders as
  String?, so the emitter appends !! (s!!.trim()).

Without the coercion, kotlinc rejects the call:

    only safe (?.) or non-null asserted (!!.) calls are allowed on a
    nullable receiver of type 'String?'.

## Check

tests/haxe/kotlin-coerce-arg/run.sh drives both arms. The positive arm
generates and compiles the normal tree (kotlinc must exit zero). The
ablation arm regenerates with -D kotlin_coerce_ablate=Argument, which skips
the Argument coercion and leaves the nullable receiver bare; kotlinc must
then exit nonzero with the nullable-receiver diagnostic. The two arms must
differ (GP-ABLATE).

kotlin.hxml names packages/compiler on the class path directly instead of
depending on -lib boring, so the fixture always measures the tree it lives
in rather than whatever the workspace haxelib projection points at
(PIT-376).
