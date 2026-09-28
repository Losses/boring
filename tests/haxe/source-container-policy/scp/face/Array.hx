package scp.face;

/**
    Foreign declaration sharing the built-in mutable array name. It is an
    ordinary source declaration of this fixture, so the analyzer must keep it
    distinct from the built-in `Array` of the root package.
**/
class Array<T> {
    public function new() {}
}
