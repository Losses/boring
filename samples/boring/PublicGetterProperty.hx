/** A public getter-only property backed by a private accessor. */

package boring;

interface HasName {
    var name(get, never):String;
}

class PublicGetterProperty implements HasName {
    public var x(get, never):Int;

    public function new(value:Int) {
        this.value = value;
    }

    final value:Int;

    function get_x():Int {
        return value + 1;
    }

    public var name(get, never):String;

    function get_name():String {
        return "getter-property";
    }
}
