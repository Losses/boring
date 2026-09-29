package cases;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceComparisonRequest;
import SourceComparisonAnalysis.SourceAdmissionResult;
#end

class ComparisonProbe {
    #if macro
    public static function run():Void {
        for (path in ["cases.left.SameKey", "cases.right.SameKey", "cases.AliasAdmission.AliasNode"]) {
            switch (Context.getType(path)) {
                case TInst(reference, arguments):
                    switch (SourceComparisonAnalysis.admit(reference, arguments, SortedKey)) {
                        case SourceAdmissionAdmitted(summary):
                            final expected = path == "cases.AliasAdmission.AliasNode" ? 2 : 1;
                            if (summary.visitedDeclarations != expected)
                                Context.error("source graph changed for " + path + ": " + summary.visitedDeclarations, Context.currentPos());
                            Sys.println("admitted " + path + " visited=" + summary.visitedDeclarations);
                        case result:
                            Context.error("source comparison rejected " + path + ": " + result, Context.currentPos());
                    }
                case _:
                    Context.error("not a record: " + path, Context.currentPos());
            }
        }
    }
    #end
}
