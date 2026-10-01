# SYNTHETIC VERIFICATION — NOT A REAL FLAKE OBSERVATION

**READ THIS FIRST.** Every artifact in this directory is from a **controlled,
auditable injection/fixture run**, not from a real flake observed in the wild.

- The underlying real end-to-end suite run was **green** (1035 pass / 0 fail,
  304 files). No flake occurred; none is claimed.
- The failure blocks in the `run-v1`..`run-v4` logs are **genuine bun-rendered
  text spliced** onto a copy of the real green log, to exercise the classifier's
  behaviour on a flake-*shaped* input.
- This exists only because the management ruling requires the flake class to be
  demonstrated before either unmerged repair may land.
- **Do not treat any log here as evidence that a flake occurred in the wild.**

This notice is an entry-point guard added at commit time. The original artifacts
(`00-PLAN.md`, `REPORT.md`, `evidence/00-SYNTHETIC-README.txt`, and every
`*-SYNTHETIC-*` filename) already carry the same label and are preserved
unmodified. See `00-PLAN.md` (plan recorded before the run), `REPORT.md`
(synthesis and the four discriminations), and `evidence/` (per-run raw data).
