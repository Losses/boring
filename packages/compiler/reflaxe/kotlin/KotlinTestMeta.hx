package reflaxe.kotlin;

/**
    The test-annotation coordinates the Kotlin target emits for generated
    test entries. Kotlin reserves the kotlin package for its own standard
    library, so the annotation lives in the runtime's own namespace instead
    of any compiled package. The literals sit in this module, outside the
    compiler-boundary-checked directory, because they name the runtime's
    package rather than an identifier of the sources being compiled.
**/
class KotlinTestMeta {
    /** The runtime package the generated test annotation is declared in. */
    public static final annotationPackage:String = "boring.test";

    /** The usage line above every generated test entry function. */
    public static final annotationUsage:String = "@boring.test.Test";

    /** The full content of the generated TestAnnotations.kt. */
    public static final annotationContent:String = "package boring.test\n\n@Target(AnnotationTarget.FUNCTION)\nannotation class Test\n";
}