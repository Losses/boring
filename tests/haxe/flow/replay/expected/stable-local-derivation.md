# Stable-local group authored expectations

The group isolates one decision: whether the emitter's comparison-position
record reaches a generated use of a local that no arm reassigns. The read stays
unguarded, because an arm would supply the fact and hide the decision.

| Line | Source rule | Expected |
| --- | --- | --- |
| skippedComparisonGuard.flag.true.null | `flag` true, the comparison runs, `b == null` holds, the guard returns | `absent` |
| skippedComparisonGuard.flag.true.box3 | `flag` true, the comparison runs and fails, `b` stays `Cell(3)` | `w:3` |
| skippedComparisonGuard.flag.false.box3 | `flag` false, the comparison is never evaluated, `b` stays `Cell(3)` | `w:3` |
| dominatingComparisonGuard.null | the comparison dominates and holds, the guard returns | `absent` |
| dominatingComparisonGuard.box3 | the comparison dominates and fails | `w:3` |
| hostBits.unitFloatIsOne | the bit pattern `1065353216` decodes to `1.0` | `true` |

## Un-authored input

`skippedComparisonGuard(false, null)` reaches the unguarded read with a null
value. The Haxe source gives that input no defined result, so it is not
authored and no run observes it. This group states no behavior rule for
dereferencing an absent value; its evidence is the emitted separator and the
target compile status of an admitted source program whose selected inputs are
all defined.
