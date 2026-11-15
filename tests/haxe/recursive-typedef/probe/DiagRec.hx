package probe;

/**
    Self-recursive anonymous typedef: the walk of the typedef body reaches
    itself through Array<DiagRec>. Before the visited set in
    CompilationUnits.collectTypeModules the TType -> def.type -> TAnonymous ->
    field -> TInst(Array,[TType]) cycle recursed until the stack overflowed.
    Leaf is the non-recursive dependency the same walk must still record.
**/
typedef DiagRec = {
    var children:Array<DiagRec>;
    var leaf:Leaf;
}
