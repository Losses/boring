/** Regression sample for a data-class constructor with an inherited super call. */

package boring;

class InheritCtorBase {
    public final baseMessage:String;

    public function new() {
        this.baseMessage = "base";
    }
}

@:dataClass
class InheritCtorOps extends InheritCtorBase {
    public final childMessage:String;

    public function new(childMessage:String) {
        this.childMessage = childMessage;
        super();
    }
}
