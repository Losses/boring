package registry;

/** The only exception the JSON reader throws, per the error taxonomy
    discipline of docs/specs/features/06-errors-and-results.md, in its own
    module so the exceptionPayloads scan of the Kotlin backend sees this
    module as the exception's home (co-locating it with other classes would
    rewrite their single-argument constructors into exception variants). */
class JsonException extends haxe.Exception {
    public final fault:JsonFault;

    public function new(fault:JsonFault) {
        this.fault = fault;
        super(JsonException.describe(fault));
    }

    public static function describe(fault:JsonFault):String {
        return switch (fault) {
            case InvalidJson: "invalid JSON";
            case TrailingInput(position): "trailing characters at offset " + position;
        };
    }
}
