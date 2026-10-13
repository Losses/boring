# Kotlin Receiver coercion fixture

P2.5. The receiver access operator (".", "?.") is written through
coerce(Receiver(memberKind)) from the presence axis, and the "!!" of a
"!!." access is embedded by the decision site (nullableAccess). Three
receiver shapes, one per method, each asserted at least once in the positive
tree:

* readFinal -- this.finalChild.label where finalChild is a final nullable
  field null-guarded first: the proof plus smart-castability holds, so the
  access renders as ".".
* readVar -- this.varChild!!.label where varChild is a var nullable field
  null-guarded first: the proof registers but Kotlin never smart-casts a
  mutable property, so the access hardens with "!!.".
* readUnproven -- value?.label where value is an unproven nullable parameter
  receiver: the access stays "?.".

Without the coercion, kotlinc rejects the dropped operator (unresolved
reference: the member-access operator is absent, leaving receiverfield text).

## Check

tests/haxe/kotlin-coerce-receiver/run.sh drives both arms. The positive arm
generates and compiles the normal tree (kotlinc must exit zero) and asserts
each of the three forms finalChild.label, varChild!!.label, value?.label
appears in coercereceiver/ReceiverCases.kt. The ablation arm regenerates
with -D kotlin_coerce_ablate=Receiver, which skips the Receiver coercion and
drops the member-access operator; kotlinc must then exit nonzero. The two
arms must differ (GP-ABLATE).

kotlin.hxml names packages/compiler on the class path directly instead of
depending on -lib boring, so the fixture always measures the tree it lives
in rather than whatever the workspace haxelib projection points at
(PIT-376).
