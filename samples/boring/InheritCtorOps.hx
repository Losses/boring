/** Regression sample for a data-class constructor with an inherited super call. */

package boring;

#if rust_output
enum InheritCtorPayload {
    Message(message:String);
}

class InheritCtorBase {
    public final baseMessage:String;

    public function new(payload:InheritCtorPayload) {
        this.baseMessage = switch (payload) {
            case Message(message): message;
        };
    }
}

@:dataClass
class InheritCtorOps extends InheritCtorBase {
    public final message:String;

    public function new(message:String) {
        this.message = message;
        super(Message(message));
    }
}
#else
@:dataClass
class InheritCtorOps {
    public final message:String;

    public function new(message:String) {
        this.message = message;
    }
}
#end
