/**
 * Constructor-parameter visibility (feature spec 27): a public field and
 * a private field, both held by constructor parameters. The private
 * field is read inside the class only, so every tree renders it with the
 * target's private spelling: `private val` on Kotlin, `private let` on
 * Swift, the `_`-prefixed name on Dart.
 */

package boring;

class PrivateHolder {
    public final shown:Int;

    final hidden:Int;

    public function new(shown:Int, hidden:Int) {
        this.shown = shown;
        this.hidden = hidden;
    }

    public function total():Int {
        return shown + hidden;
    }
}
