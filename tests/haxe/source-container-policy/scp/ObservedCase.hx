package scp;

/**
    One observed case. The adapter and analyzer answers are recorded as plain
    data for the runner to compare; display strings are evidence labels only
    and never an identity decision.
**/
typedef ObservedCase = {
    /** `authored` for a declared case, or the synthetic label. */
    final label:String;

    /** Case name; the authored field name or the synthetic name. */
    final name:String;

    /** Answer of the legacy `StaticFieldHelper.isArrayType`. */
    final mutable:Bool;

    /** Answer of the legacy `StaticFieldHelper.isReadOnlyArrayType`. */
    final readOnly:Bool;

    /** Display of the legacy `arrayElementType`, or null. */
    final element:Null<String>;

    /** Host resolution phase observed around this query. */
    final phase:String;

    /** Original typed handle constructor, kept apart from display text. */
    final inputForm:String;

    /** Analyzer wrapper variant spelling. */
    final wrapper:String;

    /** Analyzer container face variant spelling. */
    final face:String;

    /** Display of the element carried by the analyzed face, or null. */
    final analyzedElement:Null<String>;
}
