package boring;

/**
 * Single-case captured switch expressions (docs/specs/features/43-expression-block-scopes.md).
 * Each method pins a distinct expression position and payload shape.
 */
enum NoSuchElementError {
    Message(text:String);
}

enum CaptureSwitchValue {
    Text(value:String);
    Number(value:Int);
}

class CaptureSwitchOps {
    /** Return position: a single-case captured switch forwards its payload. */
    public static function describe(error:NoSuchElementError):String {
        return switch (error) {
            case Message(text): text;
        };
    }

    /** Initializer position: a single-case captured switch binds its value. */
    public static function initialized(error:NoSuchElementError):String {
        final text = switch (error) {
            case Message(value): value;
        };
        return text;
    }

    /** Return position: two captured cases provide the multi-case comparison. */
    public static function classify(value:CaptureSwitchValue):Int {
        return switch (value) {
            case Text(text): text.length;
            case Number(number): number + 1;
        };
    }

    /** Payload operation: the single captured payload participates in an expression. */
    public static function messageLength(error:NoSuchElementError):Int {
        return switch (error) {
            case Message(text): text.length + 1;
        };
    }
}
