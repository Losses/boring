# Proof: the tracked fixture survives the failure path (4cf3165d)

Status: PROVEN for c89e93fe, with a demonstrated residual limit; mechanism
since removed entirely by 2aadcb69. Full report and raw logs:
dc-warn/out/trackedfile-proof/ (REPORT.md, evidence/).

The round-215 ruling required: "After deliberately taking the failure path,
the tracked file's contents are still identical to what they were before
entering the test", and forbade counting a manual `git checkout` restore as
the fix or as proof.

## Controls (clean export, git archive HEAD at c89e93fe)

- sha256(samples/boring/MathNaNTestSupport.hx) = 1c2acf93702b177df7179aac156ab94590e844110162d71e4d6fd5b90af3018a
- `grep -c 'Test.equals'` = 5

## Pre-fix corruption reproduced (control, ab20a8af = 4cf3165d^)

SIGTERM mid-run with the stub live: count 5 -> 0,
sha256 -> 4f910e40a55a653ffe2101bf29362cd0b17dd12df371f5f0e314844d9c007500.
The mechanism is as believed; "it survived" therefore means something.

## Failure paths vs c89e93fe (finally + hidden guard)

Every run ended in test FAILURE (rc 1 / timeout 124 / forced throw); the
proof is fixture survival on the failure path, not a green test.

| path | how (no test edit) | after | verdict |
|---|---|---|---|
| throw from probe path | `--preload` made `Bun.spawn` throw inside runHaxe's try | count 5, hash 1c2acf93... | intact |
| interrupt | SIGINT to the bun PID, stub live (poller confirmed) | count 5, hash 1c2acf93... | intact |
| timeout | `timeout -s TERM 25` (CI-runner kill, stub long live) | count 5, hash 1c2acf93... | intact |
| SIGKILL (residual limit) | `--preload` hung the spawn so the stub was provably live (in-process trace: equals_count=0); SIGKILL | count **0**, hash **4f910e40...** | **corrupted** |

## Residual limit

`finally` runs only where a handler can run. SIGKILL and machine reset run
none; the SIGKILL row above demonstrates the corruption concretely at
c89e93fe (dedicated worktree), producing byte-identical damage to the
pre-fix control. bun 1.3.13 did run the restore on SIGINT/SIGTERM — that is
runtime behaviour, not a language guarantee, and must not be generalized to
other runners.

## Supersession

2aadcb69 (2026-09-30 15:37 -04:00) removed the fixture stub/restore
entirely; at HEAD runHaxe never writes the tracked file (mtime unchanged
across a full run; in-process trace: equals_count=5 at every haxe spawn).
The hazard class is eliminated rather than guarded. The SIGKILL gap above
applies only to revisions between 4cf3165d and 2aadcb69^.
