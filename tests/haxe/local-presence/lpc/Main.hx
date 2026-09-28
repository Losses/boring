package lpc;

/**
    The compile entry of the presence fact check.

    It holds no behavior. The check runs as the compile-time step that
    `run.hxml` invokes, so the check's streams and exit status are the
    compiler process's own and need no target runtime.
**/
class Main {
    public static function main():Void {}
}
