package registry;

/** Failure identity for semver parsing, in its own module so the
    Kotlin sealed fold can carry the variants inside SemverException (the
    enum's home module file is intentionally skipped on that target). */
enum SemverFault {
    InvalidCore(version:String);
    InvalidExtension(version:String);
}
