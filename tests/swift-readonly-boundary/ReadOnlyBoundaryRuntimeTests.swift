@main
struct ReadOnlyBoundaryRuntimeTests {
    // A Haxe String lowers to a UTF-16 unit array on Swift
    // (INTERFACE-REQUIREMENTS.md:235), so the oracle text has to be
    // decoded from the returned units before printing.
    static func text(_ units: [UInt16]) -> String {
        return String(decoding: units, as: UTF16.self)
    }

    static func main() {
        print("alias=\(text(ReadOnlyBoundaryOps.aliasSlots()))")
        print("effect=\(text(ReadOnlyBoundaryOps.effectfulAlias()))")
        print("reference=\(text(ReadOnlyBoundaryOps.referenceElement()))")
        print("nullable-elements=\(text(ReadOnlyBoundaryOps.nullableElements()))")
        print("nullable-literal-elements=\(text(ReadOnlyBoundaryOps.nullableLiteralElements()))")
        print("nullable-local-literal-elements=\(text(ReadOnlyBoundaryOps.localNullableLiteralElements()))")
        print("present-optional=\(text(ReadOnlyBoundaryOps.presentOptional()))")
        print("absent-optional=\(text(ReadOnlyBoundaryOps.absentOptional()))")
        print("guarded-present=\(text(ReadOnlyBoundaryOps.guardedRequired(BoringArray<Int32>([4]))))")
        print("guarded-absent=\(text(ReadOnlyBoundaryOps.guardedRequired(nil)))")
        print("guarded-field=\(text(ReadOnlyBoundaryOps.guardedField()))")
        print("null-reassigned=\(text(ReadOnlyBoundaryOps.nullReassignedView()))")
        print("cleared=\(text(ReadOnlyBoundaryOps.clearedView()))")
        print("direct-call=\(text(ReadOnlyBoundaryOps.directCallBoundary()))")
        print("constructor=\(text(ReadOnlyBoundaryOps.constructorBoundary()))")
        print("field-assignment=\(text(ReadOnlyBoundaryOps.fieldAssignmentBoundary()))")
        print("static-field=\(text(ReadOnlyBoundaryOps.staticFieldBoundary()))")
        print("return=\(text(ReadOnlyBoundaryOps.returnBoundary()))")
        print("enum=\(text(ReadOnlyBoundaryOps.enumBoundary()))")
        print("branch-true=\(text(ReadOnlyBoundaryOps.branchBoundary(true)))")
        print("branch-false=\(text(ReadOnlyBoundaryOps.branchBoundary(false)))")
        print("coalesced-null=\(text(ReadOnlyBoundaryOps.coalescedBoundary(nil)))")
        print("coalesced-present=\(text(ReadOnlyBoundaryOps.coalescedBoundary(BoringArray<Int32>([9]))))")
        print("default-omitted=\(text(ReadOnlyBoundaryOps.registeredDefaultOmittedCall()))")
        print("default-null=\(text(ReadOnlyBoundaryOps.registeredDefaultNullCall()))")
        print("default-present=\(text(ReadOnlyBoundaryOps.registeredDefaultPresentCall()))")
        print("nullable-fallback-omitted=\(text(ReadOnlyBoundaryOps.nullableFallbackOmittedCall()))")
        print("nullable-fallback-null=\(text(ReadOnlyBoundaryOps.nullableFallbackNullCall()))")
        print("nullable-fallback-present=\(text(ReadOnlyBoundaryOps.nullableFallbackPresentCall()))")
        print("guarded-nullable-fallback=\(text(ReadOnlyBoundaryOps.guardedNullableFallbackBoundary(BoringArray([45]))))")
        print("traverse-readonly=\(text(ReadOnlyBoundaryOps.traverseReadOnlyView(ReadOnlyArray(BoringArray<Int32>([3, 4, 5])))))")
    }
}
