package reflaxe.kotlin;

/**
    The test-annotation coordinates the Kotlin target emits for generated
    test entries. Kotlin reserves the kotlin package for its own standard
    library, so the annotation lives in the runtime's own namespace.
    The literals sit in this module, outside the
    compiler-boundary-checked directory, because they identify the runtime
    package. The package containing compiled source varies by consumer.
**/
class KotlinTestMeta {
    /** The runtime package the generated test annotation is declared in. */
    public static final annotationPackage:String = "boring.test";

    /** The usage line above every generated test entry function. */
    public static final annotationUsage:String = "@boring.test.Test";

    /** The full content of the generated TestAnnotations.kt. */
    public static final annotationContent:String = "package boring.test\n\n@Target(AnnotationTarget.FUNCTION)\nannotation class Test\n";
}