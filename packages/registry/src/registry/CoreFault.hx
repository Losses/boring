package registry;

/** Failure identity for the generator core, in its own module so the
Kotlin sealed fold can carry the variants inside CoreException (the
enum's home module file is intentionally skipped on that target). */
enum CoreFault {
	Config(text:String);
	Tree(text:String);
}
