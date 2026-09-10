package boring;

import boring.ValueTypeOps.FontFaceId;
import boring.ValueTypeOps.Ic;

/** Cross-module uses of both marked wrapper shapes. */
@:dataClass
class OptionalIcRecord {
    public final indent:Null<Ic>;

    public function new(indent:Null<Ic>) {
        this.indent = indent;
    }
}

class ValueTypeConsumer {
    public static function arithmetic():Float {
        final first:Ic = new Ic(2.0);
        final total = first + Ic.ZERO;
        return total.toPx(3.0);
    }

    public static function equalRepresentations():Bool {
        return new Ic(2.0) == new Ic(2.0);
    }

    public static function staticValue():Float {
        return Ic.ZERO.toPx(5.0);
    }

    public static function blankRejected():Bool {
        var rejected = false;
        try {
            new FontFaceId(" ");
        } catch (_:ValueException) {
            rejected = true;
        }
        return rejected;
    }

    public static function optionalIcPresent():Float {
        final record = new OptionalIcRecord(new Ic(2.0));
        final indent = record.indent;
        if (indent == null)
            return -1.0;
        return indent == null ? -1.0 : 2.0;
    }

    public static function renderedId():String {
        final id:FontFaceId = new FontFaceId("face");
        return id.toString();
    }
}
