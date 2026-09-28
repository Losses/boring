# Group A authored expectations

Every expectation below is derived from the Haxe source rules and arithmetic,
before any run. The Haxe reference run is then compared against these lines, so
the reference run confirms the derivation; it does not define it. The line
names come from `flow/normalized/FlowMain.hx`; the input labels keep the
authored `box` spelling of the earlier attempts.

`Cell.width` is the constructor argument. The final null test of every case is
`b == null ? fallback : "w:" + b.width`, so the value of a present `Cell(n)` is
the decimal text of `n` prefixed with `w:`.

| Line | Source rule | Expected |
| --- | --- | --- |
| guardInsideSkippedBranch.flag.true.null | `flag` true, `b == null` holds, so the repair writes `Cell(6)`; the normalization reads 6 | `w:6` |
| guardInsideSkippedBranch.flag.false.null | `flag` false, so the comparison is never evaluated and `b` stays null; the fallback applies | `absent` |
| guardInsideSkippedBranch.flag.false.box3 | `flag` false, `b` stays `Cell(3)` | `w:3` |
| guardInsideSkippedBranch.flag.true.box3 | the comparison fails, no write | `w:3` |
| writeAfterExitGuard.box3.null | the guard passes, then `b = null`; the fallback applies | `cleared` |
| writeAfterExitGuard.box3.box1 | the guard passes, then `b = Cell(1)` | `w:1` |
| writeAfterExitGuard.null.box1 | the guard returns | `absent` |
| writeAfterExitGuard.null.null | the guard returns | `absent` |
| joinedWrite.true.box3.null | the writing arm runs with a null replacement | `cleared` |
| joinedWrite.true.box3.box2 | the writing arm runs with `Cell(2)` | `w:2` |
| joinedWrite.false.box3.null | the writing arm is skipped, `b` stays `Cell(3)` | `w:3` |
| joinedWrite.false.box3.box2 | the writing arm is skipped, `b` stays `Cell(3)` | `w:3` |
| joinedWrite.true.null.box2 | the guard returns | `absent` |
| joinedExitingWrite.true.box3.null | the writing arm returns the constant `exiting` | `exiting` |
| joinedExitingWrite.false.box3.null | the writing arm is skipped | `w:3` |
| joinedExitingWrite.false.box3.box2 | the writing arm is skipped | `w:3` |
| joinedExitingWrite.true.null.box2 | the guard returns | `absent` |
| normalizationPresentControl.box3 | the guard passes, so the normalization condition is false | `w:3` |
| normalizationPresentControl.null | the guard returns | `absent` |
| normalizedBinding.box3 | the binding takes the arm `b.width` | `w:3` |
| normalizedBinding.null | the binding takes the fallback `-1` | `w:-1` |
| sequentialWriteAfterChain.box4 | `held` is `4 > 0`, so the write sets `b = null` | `cleared` |
| sequentialWriteAfterChain.box0 | `held` is `0 > 0`, so no write | `w:0` |
| sequentialWriteAfterChain.null | `held` is false, `b` stays null | `cleared` |
| hostBits.unitFloatIsOne | `1065353216` is the IEEE-754 bit pattern of `1.0`, so the comparison holds | `true` |

`HostBits.unitFloatIsOne` is the declared runtime dependency of the emitted
test host, and it is not a flow case.
