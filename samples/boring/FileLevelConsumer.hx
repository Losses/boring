package boring;

/** Cross-module consumer of the public file-scope functions. */
class FileLevelConsumer {
    public static function publicResult():Int {
        return FileLevelOps.publicValue(7);
    }

    public static function privateResultThroughPublic():Int {
        return FileLevelOps.publicWithPrivate(3);
    }
}
