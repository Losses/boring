import cases.RecursiveKey
import cases.AliasNode
import cases.EnumKeyRecord
import cases.Shade
import cases.compareAliasNode
import cases.compareEnumKeyRecord
import cases.compareRecursiveKey
import cases.left.SameKey as LeftKey
import cases.left.compareSameKey as compareLeft
import cases.right.SameKey as RightKey
import cases.right.compareSameKey as compareRight
import comparison.ParameterCompositionCases

fun main() {
    check(compareLeft(LeftKey(1), LeftKey(2)) < 0)
    check(compareRight(RightKey("a"), RightKey("z")) < 0)
    check(compareRecursiveKey(RecursiveKey(1, null), RecursiveKey(1, RecursiveKey(2, null))) < 0)
    check(compareRecursiveKey(RecursiveKey(1, RecursiveKey(3, null)), RecursiveKey(1, RecursiveKey(2, null))) > 0)
    check(compareAliasNode(AliasNode(1, null), AliasNode(1, AliasNode(2, null))) < 0)
    check(compareAliasNode(AliasNode(1, AliasNode(3, null)), AliasNode(1, AliasNode(2, null))) > 0)
    check(ParameterCompositionCases.observe() == "direct=AB;unused=AB;nested=AB;nullable=NV;sequence=AB")
    check(compareEnumKeyRecord(EnumKeyRecord(Shade.Mid, 0), EnumKeyRecord(Shade.Bright, 0)) < 0)
    check(compareEnumKeyRecord(EnumKeyRecord(Shade.Bright, 0), EnumKeyRecord(Shade.Mid, 0)) > 0)
    check(compareEnumKeyRecord(EnumKeyRecord(Shade.Dim, 1), EnumKeyRecord(Shade.Dim, 2)) < 0)
    println("same-name=ordered recursive-alias=ordered generic=ordered enum=ordered")
}
