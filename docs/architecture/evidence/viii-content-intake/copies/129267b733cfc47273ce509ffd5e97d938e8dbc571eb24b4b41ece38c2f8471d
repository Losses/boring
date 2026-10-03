# Evidence package for the round-112 ruling (R2 + R3, complete)

Produced exactly to the round-112 ruling's single instruction: for `2aadcb69` and
`4f80322c` (with `eec707b9`'s corresponding record retained), a temporary detached
worktree's full raw output, an independent export with a per-file manifest, and the
correspondence of all of it to commit ids and the reviews that judged them.

Read-only: no merge, no flake injection, no change to any implementation.

## The distinction this package exists to fix

The earlier package proved **commit-tree content identity** - that the bytes are
reconstructible from the hash. The ruling correctly pointed out that this is **not**
R2 as defined: `git archive <hash>` proves the commit's tree, not that an actual
checkout of it has an empty `git status --porcelain`. Those are different claims, and
the earlier package also gave only aggregate counts, no per-file manifest, no raw
output, and no checksummed archive. This package supplies all four.

## Correspondence

| Commit (full id) | Tree id | Reviewed by | Review judged | R2 | R3 |
|---|---|---|---|---|---|
| `2aadcb6978d81705379892d2b382671b3458e753` | `91151878a6ba0890fda27eddb438d277ac8e9555` | `02507c97` | contract 3 conditions 1-2 (npm artifact determinism) | `<hash>.R2-worktree.txt` | `<hash>.R3-manifest.txt` + `<hash>.export.tar` |
| `4f80322c7ee1ebff5bc893726b4f356a71785ff5` | (in its `.R2-worktree.txt`) | `02507c97`-adjacent (CI attribution) | contract 3 condition 3, attribution half | same | same |
| `eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e` | (in its `.R2-worktree.txt`) | `e32fd55e` | contract 3 condition 4 | same | same |

## What each file is

- **`<hash>.R2-worktree.txt`** - the raw output of creating a **detached worktree at
  that commit** and running `git rev-parse HEAD`, `git rev-parse HEAD^{tree}` and
  `git status --porcelain` inside it. All three report **0 porcelain lines**, i.e. the
  checkout of that commit is clean. This is R2, and it no longer depends on the live
  worktree - which was the reason two verifiers reported it ABSENT.
- **`<hash>.R3-manifest.txt`** - the **per-file** manifest: 1455 entries of
  `blob-oid  path`, derived from the commit via `git ls-tree -r`. A verifier can now
  check any single file rather than trusting an aggregate.
- **`<hash>.export.tar`** and **`<hash>.export.tar.sha256`** - the independent export
  and its checksum, so the content is independently obtainable and its identity is
  pinned by hash.

## Verified in this package

| Commit | R2 porcelain lines | manifest entries | export tar sha256 |
|---|---|---|---|
| `2aadcb69` | **0** | 1455 | `38b6d43a3418d8602eeaa6fed381f06ff3eee7a29ba4292f41cb5a87a2a9a2e0` |
| `4f80322c` | **0** | 1455 | `74c9fe6cea584658d2c0490824a9422548ed51a6ec494edc3da6f7041b6c4cd8` |
| `eec707b9` | **0** | 1455 | `ad7004d70cd2bab86f81c69ab4d8c209ef2c0fd491eb95fc2f9e312213a77688` |

## What this still does not claim

It does not re-run the two reviews' measurements, and it does not touch contract 3
condition 3, whose flake class remains **NOT-EXERCISED**. Merging remains withheld
pending the ruling's decision, and nothing here authorizes a merge.
