package probe;

/** Mutual recursion, second half: closes the cycle back to MutualA. */
typedef MutualB = {
    var peers:Array<MutualA>;
}
