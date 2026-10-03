# viii-content-intake — content-addressed intake preparation

Content-addressed copies of dc-warn evidence/source bytes that were
independently verified in five intake batches and are not already present as
bare bytes in the Boring HEAD full tree.

## Scope

- Source index: `intake-union-index/union-all.tsv` (complete original-path
  mapping across intake-batch-0/1/2/2-supplement/source-next).
- Content objects: `copies/<sha256>` (flat, named by bare SHA256 of bytes).
- Every object is deduplicated across batches by its bare SHA256, and every
  original path alias is retained in `path-map.tsv`.

## Counts

- Boring HEAD unique blob content SHA256: 2205
- Candidates before exclusion: 7279 unique sha256 / 17201 paths
- Excluded (already in Boring HEAD): 0
- Kept: 7279 unique sha256 / 17201 original paths / 89669993 bytes (85.52 MiB)

## Verification

- `sha256sum -c SHA256SUMS` from this directory returns rc=0 over 7279 entries.
- Every copied object was re-hashed and byte-size checked against its index
  record immediately after copy.

## Sensitive exclusions (not copied, content not printed)

  - bytefix-xcheck2/evidence/xc2-batch.env.txt
  - bytefix-xcheck2/evidence/xc2-controls2.env.txt
  - bytefix-xcheck2/evidence/xc2-markers.env.txt
  - bytefix-xcheck2/evidence/xc2-controls.env.txt

## Duplicate shas excluded (batch-0 correction, originals not deleted)

  - 53c234e5e8472b6ac51c1ae1cab3fe06fad053beb8ebfd8977b010655bfdd3c3
  - 8a42ea73a12435ae8a88d184fdc284a3cac5e0e1f3cd66014cc931fdf6893cfd

## Remaining (not covered here)

This preparation covers only the five independently verified batches via the
frozen union index. It is not a remote rescan of dc-warn/out, does not assert
global uniqueness or complete path recovery, and does not sign the overall
task t-muqaclrd-yxqk done.

## Path-index correction (2026-10-03 per independent verification)

1,374 missing ledger aliases (identified by independent verification seat 6)
were mechanically merged into path-map.tsv from
`.tq-logs/viii/content-intake-independent-verify/missing-aliases-1374.tsv`,
cross-referenced against `intake-union-index/all-path-map.tsv` for batch
attribution. All 1,374 (path, sha, bytes) triples were verified against the
fac85046 ledger (32,902 records). No content objects were changed; copies/
and SHA256SUMS remain at 7,279 objects / 89,669,993 bytes.

Post-merge path-map: 17,201 rows (15,827 + 1,374, zero (sha,path) collisions).
