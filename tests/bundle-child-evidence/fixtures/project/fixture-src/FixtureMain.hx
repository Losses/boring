package;

/**
 * One class the fixture project compiles. It uses a deprecated member so a
 * successful generation writes a warning shaped line on standard error and
 * still exits zero, which is the case the evidence must retain.
 */
class FixtureMain {
    public static function main():Void {
        DeprecationSource.oldThing();
    }
}
