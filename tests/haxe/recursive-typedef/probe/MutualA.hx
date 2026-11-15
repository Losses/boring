package probe;

/** Mutual recursion, first half: reaches MutualB through Array<MutualB>. */
typedef MutualA = {
    var peers:Array<MutualB>;
}
