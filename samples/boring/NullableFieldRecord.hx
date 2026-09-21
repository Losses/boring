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
}
