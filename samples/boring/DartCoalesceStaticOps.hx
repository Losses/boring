package boring;

#if dart_output
/**
 * A static field initializer calling a constructor whose omitted
 * arguments carry body-coalescing defaults: the default expressions
 * reference a same-class static and another module's static, and the
 * emitted call must qualify both through the import prefixes, never
 * the raw Haxe dotted path.
 */
class DartCoalesceStaticOps {
    public static function preset():DartCoalesceReceiver {
        return DartCoalesceReceiver.preset;
    }

    public static function custom(mode:Int):DartCoalesceReceiver {
        return new DartCoalesceReceiver(mode);
    }
}
#end
