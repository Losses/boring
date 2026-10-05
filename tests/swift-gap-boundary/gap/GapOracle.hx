package gap;

import std.ReadOnlyArray;
import gap.Gap.GapChoice;
import gap.Gap.GapExtra;
import gap.Gap.GapStatics;
import gap.Gap.GapExplicitReturn;
import gap.Gap.GapPaths;
import gap.Gap.GapPaths2;

/** Independent Haxe oracle for the gap fixture runtime comparison. Calls
    every fixture function and prints the observed result, including the
    actual value of tryLocal(true) (the catch path returns sourceSecond(),
    so the length is 1), not just "no-throw". The Swift harness prints the
    same lines; byte-identical output proves unchanged runtime behavior. */
class GapOracle {
    static function arr(a:ReadOnlyArray<Int>):String {
        final parts = [for (i in 0...a.length) Std.string(a[i])];
        return "[" + parts.join(",") + "]";
    }

    static function main() {
        // controlTernary: ternary initializer, destination ReadOnlyArray.
        Sys.println("controlTernary.true = " + Gap.controlTernary(true));
        Sys.println("controlTernary.false = " + Gap.controlTernary(false));
        // switchLocal: switch initializer.
        Sys.println("switchLocal.One = " + Gap.switchLocal(GapChoice.One));
        Sys.println("switchLocal.Two = " + Gap.switchLocal(GapChoice.Two));
        // tryLocal: try initializer; true path throws then catch returns [3] -> length 1.
        Sys.println("tryLocal.false = " + Gap.tryLocal(false));
        Sys.println("tryLocal.true = " + Gap.tryLocal(true));
        // switchReturnPosition: switch in return position.
        Sys.println("switchReturnPosition.One = " + arr(Gap.switchReturnPosition(GapChoice.One)));
        Sys.println("switchReturnPosition.Two = " + arr(Gap.switchReturnPosition(GapChoice.Two)));
        // GapExtra.ifReturnPosition: ternary in return position.
        Sys.println("ifReturnPosition.true = " + arr(GapExtra.ifReturnPosition(true)));
        Sys.println("ifReturnPosition.false = " + arr(GapExtra.ifReturnPosition(false)));
        // GapExtra.switchArgument: switch as an argument (expression position).
        Sys.println("switchArgument.One = " + GapExtra.switchArgument(GapChoice.One));
        Sys.println("switchArgument.Two = " + GapExtra.switchArgument(GapChoice.Two));
        // GapExtra.switchReturnLocal: switch in return position, arm value is a plain local.
        Sys.println("switchReturnLocal.One = " + arr(GapExtra.switchReturnLocal(GapChoice.One, [1, 2])));
        Sys.println("switchReturnLocal.Two = " + arr(GapExtra.switchReturnLocal(GapChoice.Two, [3])));
        // GapExtra.consume: consume a ReadOnlyArray.
        Sys.println("consume.One = " + GapExtra.consume(Gap.sourceFirst()));
        Sys.println("consume.Two = " + GapExtra.consume(Gap.sourceSecond()));
        // GapStatics.values: static read-only array field.
        Sys.println("statics.values = " + arr(GapStatics.values));
        // GapExplicitReturn.switchExplicitReturn: switch arm with explicit return.
        Sys.println("switchExplicitReturn.One = " + arr(GapExplicitReturn.switchExplicitReturn(GapChoice.One)));
        Sys.println("switchExplicitReturn.Two = " + arr(GapExplicitReturn.switchExplicitReturn(GapChoice.Two)));
        // GapPaths.tryReturn: try in return position.
        Sys.println("tryReturn.false = " + arr(GapPaths.tryReturn(false)));
        Sys.println("tryReturn.true = " + arr(GapPaths.tryReturn(true)));
        // GapPaths.switchAssignPath: assignment whose value is a switch.
        Sys.println("switchAssignPath.One = " + GapPaths.switchAssignPath(GapChoice.One));
        Sys.println("switchAssignPath.Two = " + GapPaths.switchAssignPath(GapChoice.Two));
        // GapPaths2.switchStatementPath: statement-position switch.
        Sys.println("switchStatementPath.One = " + GapPaths2.switchStatementPath(GapChoice.One));
        Sys.println("switchStatementPath.Two = " + GapPaths2.switchStatementPath(GapChoice.Two));
        // GapPaths2.tryStatementAssignPath: statement-position try.
        Sys.println("tryStatementAssignPath.false = " + GapPaths2.tryStatementAssignPath(false));
        Sys.println("tryStatementAssignPath.true = " + GapPaths2.tryStatementAssignPath(true));
    }
}
