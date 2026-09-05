package boring;

/**
 * A record with an interface-typed field (feature spec 31 amendment). An
 * interface that declares toString prints through the field's own member:
 * the singleton variant prints its bare name and the record variant prints
 * its labeled form, the same two states the Kotlin data class native print
 * renders for the same source.
 */
@:sealed
interface RichTextRole {
    function toString():String;
}

class Background implements RichTextRole {
    public static final instance:Background = new Background();

    private function new() {}
}

@:dataClass
class Link implements RichTextRole {
    public final target:String;

    public function new(target:String) {
        this.target = target;
    }
}

@:dataClass
class RichTextSpan {
    public final role:RichTextRole;
    public final note:Null<RichTextRole>;

    public function new(role:RichTextRole, note:Null<RichTextRole>) {
        this.role = role;
        this.note = note;
    }
}

class RecordInterfaceOps {
    public static function singletonSpan():RichTextSpan {
        return new RichTextSpan(Background.instance, null);
    }

    public static function recordSpan():RichTextSpan {
        return new RichTextSpan(new Link("tiqian"), Background.instance);
    }
}
