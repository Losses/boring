# p08-behaviour-review evidence intake (H9, 2026-10-01)

Byte-for-byte mirror of `dc-warn/out/p08-behaviour-review/`, the P08 behaviour
review cited by GATE-LEDGER row P08-4 as "non-accepting". Copied `cp -a` to
local `/tmp` before any reading or hashing (PIT-178: reads directly off the
dc-warn sshfs mount can serve stale content), cross-checked by sha256 against
the mount (47/47 files identical), then committed with `SHA256SUMS.txt`
covering all 47 mirrored files.

`README.md` and `SHA256SUMS.txt` are intake artifacts written by H9 on
2026-10-01; everything else is review output, unmodified. No file was renamed
or restructured during intake.
