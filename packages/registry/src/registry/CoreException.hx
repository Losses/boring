package registry;

/** The only exception the generator core throws, in its own module so
    the exceptionPayloads scan of the Kotlin backend sees this module as
    the exception's home (co-locating it with other classes would rewrite
    their single-argument constructors into exception variants). */
class CoreException extends haxe.Exception {
    public final error:CoreFault;

    public function new(error:CoreFault) {
        this.error = error;
        super(CoreException.describeError(error));
    }

    public static function describeError(error:CoreFault):String {
        return switch (error) {
            case Config(text): text;
            case Tree(text): text;
        };
    }
}
