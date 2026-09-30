# Entry-gate R2/R3 evidence package (committed as an evidence-only commit)

Authorised by the round-128 ruling as a **separate evidence commit**, not mixed with
implementation, tests or workflow changes.

## What R2 and R3 are, and why this package exists

The ledger's entry gate requires, before any entry may claim "on the line /
delivered / frozen": a traceable commit hash, **a clean working-tree proof for that
hash**, **content exported independently of any live worktree**, and a
claim-versus-commit check by someone other than the implementer.

Two independent verifiers confirmed every technical claim and then both failed the
entry on the same two requirements, giving the same reason: the live worktree sits
on a different branch that keeps being rewritten, so a clean working tree *for the
commit under review* is not obtainable from it. That reasoning was correct, and it
exposed the real defect - the gate said what was required but never how to produce
it. `tools/gate-proof/verify-commit.ts` (`bun run gate:verify -- <commit-ish>`) now
produces it mechanically, and this package is the instance that closed the gate.

## Contents per commit

| File | What it is |
|---|---|
| `<hash>.R2-worktree.txt` | raw output of a **detached worktree at that commit**, showing `git rev-parse HEAD`, `git rev-parse HEAD^{tree}` and `git status --porcelain` - **all three report 0 porcelain lines**. This is R2, and it no longer depends on the live worktree. |
| `<hash>.R3-manifest.txt` | the **per-file** manifest: 1455 entries of `blob-oid  path` from `git ls-tree -r <hash>`, so a verifier can check any single file instead of trusting an aggregate. |
| `<hash>.export.tar.sha256` | the SHA-256 of the independent export of that commit. |
| `MAPPING.md` | commit full id, tree id, which review judged it, and which files carry its evidence. |
| `SHA256SUMS.txt` | checksums of this package's own files. |

## Why the export tarballs are not committed here

Each `<hash>.export.tar` is **reproducible from the commit alone** - that is exactly
what the recorded checksum asserts - so committing ~32 MB of archives would add
little and would nearly double a repository that is 33 MB in total. Verified before
omitting them:

```
git archive --format=tar <commit> | sha256sum
2aadcb69 -> 38b6d43a3418d8602eeaa6fed381f06ff3eee7a29ba4292f41cb5a87a2a9a2e0
4f80322c -> 74c9fe6cea584658d2c0490824a9422548ed51a6ec494edc3da6f7041b6c4cd8
eec707b9 -> ad7004d70cd2bab86f81c69ab4d8c209ef2c0fd491eb95fc2f9e312213a77688
```

Each equals its `.export.tar.sha256` above, so a verifier can regenerate the archive
and compare. If an independent archive is ever wanted in-tree, that is a one-command
reproduction, not a missing artefact.

## Scope

Evidence only. No implementation, test or workflow file is touched by this commit.

## What this package does not claim

Content identity only. It does not re-run either review's measurements, and it says
nothing about contract 3's flake class, whose status is recorded separately as
`EXERCISED (SYNTHETIC FLAKE-SHAPED INPUT; NO REAL FLAKE OBSERVED)`.
