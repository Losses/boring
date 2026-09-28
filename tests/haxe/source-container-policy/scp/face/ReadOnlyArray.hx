package scp.face;

/**
    Foreign declaration sharing the read-only array name. It is an ordinary
    source declaration of this fixture. It is distinct from the reserved
    `std.ReadOnlyArray`, and the analyzer must keep the two apart. Its
    representation is irrelevant to the case: only the written identity is
    classified.
**/
abstract ReadOnlyArray<T>(Int) from Int {}
