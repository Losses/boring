/** A public getter-only property backed by a private accessor. */

package boring;

class PublicGetterProperty {
    public var x(get, never):Int;

    public function new(value:Int) {
        this.value = value;
    }

    final value:Int;

    function get_x():Int {
        return value + 1;
    }
}
