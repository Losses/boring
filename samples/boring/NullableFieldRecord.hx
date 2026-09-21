package boring;

/**
 * A printed class record whose constructor places the nullable parameter
 * after a required one while the field declarations keep the other order
 * (docs/specs/features/31-record-tostring-member.md, feature spec 37 rule
 * 3). The two orders differ, so the Kotlin target keeps the synthesized
 * member as an explicit override and does not use the native data class
 * print, and that member is what renders a null field.
 */
@:dataClass
class NullableFieldRecord {
    public final name:String;
    public final code:Null<Int>;
    public final label:Null<String>;
    public final words:Null<Array<String>>;

    public function new(name:String, ?label:Null<String>, ?code:Null<Int>, ?words:Null<Array<String>>) {
        this.name = name;
        this.label = label;
        this.code = code;
        this.words = words;
    }

    /**
        The nullable label as the left operand of a concatenation with a
        literal. Kotlin's String?.plus(Any?) renders a null receiver as
        "null", the text Std.string(null) produces, so the expression must
        not assert the field (docs/specs/features/31-record-tostring-member.md).
    **/
    public function labelPlusLiteral():String {
        return this.label + "l";
    }

    /** The nullable label as the right operand of a concatenation with a literal. */
    public function literalPlusLabel():String {
        return "l" + this.label;
    }

    /** The nullable Int field as the left operand, which renders through its own conversion. */
    public function codePlusLiteral():String {
        return this.code + "c";
    }
}
