/** An interface declaring a getter-only property. */

package boring;

interface InterfaceGetterProperty {
    var name(get, never):String;
}

class InterfaceGetterPropertyImpl implements InterfaceGetterProperty {
    public var name(get, never):String;

    public function new(value:String) {
        this._value = value;
    }

    final _value:String;

    function get_name():String {
        return _value;
    }
}

/** Reads the getter-only property through a protocol-typed receiver. */
class InterfaceGetterPropertyUse {
    public static function nameOf(value:InterfaceGetterProperty):String {
        return value.name;
    }
}
