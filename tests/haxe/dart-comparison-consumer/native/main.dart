import '../dart-gen/lib/dartcomparison/comparison_cases.dart' as cases;
import '../dart-gen/lib/dartcomparison/enum_cases.dart' as enums;
import '../dart-gen/lib/boring/printed_enum_ops.dart' as marks;
import '../dart-gen/lib/boring/printed_collection.dart' as flags;
import '../dart-gen/lib/boring/printed_sorted_fields.dart' as nullable;
import '../dart-gen/lib/comparison/parameter_composition_cases.dart' as parameters;
import '../dart-gen/lib/dartcomparison/left/same.dart' as left;
import '../dart-gen/lib/dartcomparison/left/left_wrapper.dart' as leftWrap;
import '../dart-gen/lib/dartcomparison/right/same.dart' as right;
import '../dart-gen/lib/dartcomparison/right/right_wrapper.dart' as rightWrap;

void check(String name, int actual, int expected) {
  if (actual.sign != expected.sign) {
    throw StateError('$name: expected sign $expected, got $actual');
  }
  print('$name=$actual');
}

void main() {
  check('payload-order', enums.compareAliasKey(enums.AliasKey(marks.PrintedMarkPlain()), enums.AliasKey(marks.PrintedMarkRing(1))), -1);
  check('payload-reverse', enums.compareAliasKey(enums.AliasKey(marks.PrintedMarkTag('x', 1)), enums.AliasKey(marks.PrintedMarkRing(9))), 1);
  check('payload-ordinal-only', enums.compareAliasKey(enums.AliasKey(marks.PrintedMarkRing(1)), enums.AliasKey(marks.PrintedMarkRing(99))), 0);
  check('payload-null', nullable.comparePrintedNullableMark(nullable.PrintedNullableMark(null), nullable.PrintedNullableMark(marks.PrintedMarkPlain())), -1);
  check('payload-present', nullable.comparePrintedNullableMark(nullable.PrintedNullableMark(marks.PrintedMarkRing(1)), nullable.PrintedNullableMark(marks.PrintedMarkTag('x', 1))), -1);
  check('payload-sequence', flags.comparePrintedEnumCollection(flags.PrintedEnumCollection([flags.PrintedFlagSilent()]), flags.PrintedEnumCollection([flags.PrintedFlagSteps(1)])), -1);
  check('payload-prefix', flags.comparePrintedEnumCollection(flags.PrintedEnumCollection([]), flags.PrintedEnumCollection([flags.PrintedFlagSilent()])), -1);
  check('native-order', enums.compareNativeKey(enums.NativeKey(enums.NativeOrder.zebra), enums.NativeKey(enums.NativeOrder.alpha)), -1);
  print('enum-callbacks=' + enums.observe());
  check('first-field', cases.compareMultiKey(
    cases.MultiKey(1, 9, [9]), cases.MultiKey(2, null, [0])), -1);
  check('nullable-field', cases.compareMultiKey(
    cases.MultiKey(1, null, [9]), cases.MultiKey(1, 0, [0])), -1);
  check('later-field', cases.compareMultiKey(
    cases.MultiKey(1, 0, [1, 9]), cases.MultiKey(1, 0, [2, 0])), -1);
  check('equal', cases.compareMultiKey(
    cases.MultiKey(1, null, [1]), cases.MultiKey(1, null, [1])), 0);
  check('nullable-element', cases.compareNullableElementsKey(
    cases.NullableElementsKey([null, 9]), cases.NullableElementsKey([0, 0])), -1);
  check('nullable-element-later', cases.compareNullableElementsKey(
    cases.NullableElementsKey([0, 1]), cases.NullableElementsKey([0, 2])), -1);
  check('recursive', cases.compareChainKey(
    cases.ChainKey(1, cases.ChainKey(2, null)),
    cases.ChainKey(1, cases.ChainKey(3, null))), -1);
  check('recursive-null', cases.compareChainKey(
    cases.ChainKey(1, null), cases.ChainKey(1, cases.ChainKey(0, null))), -1);
  check('left-same', leftWrap.compareLeftWrapper(
    leftWrap.LeftWrapper(left.Same(1)), leftWrap.LeftWrapper(left.Same(2))), -1);
  check('right-same', rightWrap.compareRightWrapper(
    rightWrap.RightWrapper(right.Same(2)), rightWrap.RightWrapper(right.Same(1))), 1);
  check('null-seq-cross', cases.compareNullSequenceCrossKey(
    cases.NullSequenceCrossKey(null), cases.NullSequenceCrossKey([left.Same(1)])), -1);
  check('null-seq-cross-order', cases.compareNullSequenceCrossKey(
    cases.NullSequenceCrossKey([left.Same(1)]), cases.NullSequenceCrossKey([left.Same(2)])), -1);
  print('parameter-composition=' + parameters.observe());
}
