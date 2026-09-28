package lpc;

/** One observed use and the facts the analysis stated for it.

    The label fields are evidence labels only. No identity decision reads
    them; the expectation table in `Main` compares them as authored text.
**/
typedef ObservedUse = {
    /** The case function the use belongs to, suffixed `#n` inside a nested
        function literal. */
    final caseName:String;

    /** `use` for a marker argument, `guardSubject` for the subject of a null
        comparison, `bodyExit` for the body's reachable exits, and
        `ambiguousCount` for the ambiguous physical nodes of the case. */
    final kind:String;

    /** Index of this row within its case and kind, in traversal order. */
    final index:Int;

    /** `local` when the use reads a binding of this body, else `nonLocal`. */
    final subject:String;

    final availability:String;

    final knowledge:String;

    final presence:String;

    final reason:String;
}
