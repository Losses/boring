// Independent Swift harness for the gap fixture runtime comparison.
// Calls every fixture function and prints the observed result, matching
// the Haxe oracle (gap.GapOracle) line-for-line. Byte-identical output
// between the Swift run and the Haxe oracle shows only that the tested
// call outputs agree; it does not prove general runtime behavior.

func arr(_ a: ReadOnlyArray<Int32>) -> String {
    var parts: [String] = []
    for x in a { parts.append(String(x)) }
    return "[" + parts.joined(separator: ",") + "]"
}

print("controlTernary.true = \(Gap.controlTernary(true))")
print("controlTernary.false = \(Gap.controlTernary(false))")
print("switchLocal.One = \(Gap.switchLocal(GapChoice.one))")
print("switchLocal.Two = \(Gap.switchLocal(GapChoice.two))")
print("tryLocal.false = \(try Gap.tryLocal(false))")
print("tryLocal.true = \(try Gap.tryLocal(true))")
print("switchReturnPosition.One = \(arr(Gap.switchReturnPosition(GapChoice.one)))")
print("switchReturnPosition.Two = \(arr(Gap.switchReturnPosition(GapChoice.two)))")
print("ifReturnPosition.true = \(arr(GapExtra.ifReturnPosition(true)))")
print("ifReturnPosition.false = \(arr(GapExtra.ifReturnPosition(false)))")
print("switchArgument.One = \(GapExtra.switchArgument(GapChoice.one))")
print("switchArgument.Two = \(GapExtra.switchArgument(GapChoice.two))")
print("switchReturnLocal.One = \(arr(GapExtra.switchReturnLocal(GapChoice.one, TiqianArray<Int32>([1, 2]))))")
print("switchReturnLocal.Two = \(arr(GapExtra.switchReturnLocal(GapChoice.two, TiqianArray<Int32>([3]))))")
print("consume.One = \(GapExtra.consume(ReadOnlyArray(Gap.sourceFirst())))")
print("consume.Two = \(GapExtra.consume(ReadOnlyArray(Gap.sourceSecond())))")
print("statics.values = \(arr(GapStatics.values))")
print("switchExplicitReturn.One = \(arr(GapExplicitReturn.switchExplicitReturn(GapChoice.one)))")
print("switchExplicitReturn.Two = \(arr(GapExplicitReturn.switchExplicitReturn(GapChoice.two)))")
print("tryReturn.false = \(arr(try GapPaths.tryReturn(false)))")
print("tryReturn.true = \(arr(try GapPaths.tryReturn(true)))")
print("switchAssignPath.One = \(GapPaths.switchAssignPath(GapChoice.one))")
print("switchAssignPath.Two = \(GapPaths.switchAssignPath(GapChoice.two))")
print("switchStatementPath.One = \(GapPaths2.switchStatementPath(GapChoice.one))")
print("switchStatementPath.Two = \(GapPaths2.switchStatementPath(GapChoice.two))")
print("tryStatementAssignPath.false = \(try GapPaths2.tryStatementAssignPath(false))")
print("tryStatementAssignPath.true = \(try GapPaths2.tryStatementAssignPath(true))")
