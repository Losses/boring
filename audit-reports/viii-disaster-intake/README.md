# VIII Disaster Intake — Three-Report Ingestion

## Scope

This directory contains the intake result for **three** reports only. It is a
**partial** ingestion, NOT a complete archive of the VIII disaster evidence. It
does not claim any directory-count reduction and does not constitute overall
acceptance of the VIII disaster recovery.

Source and archive-counterpart paths below are relative to the outer tq-workspace repository, not this Boring repository.

The three reports are:

| Report | Source | Archive counterpart | Intake status |
|--------|--------|---------------------|---------------|
| `fsmissing/REPORT.md` | `dc-warn/out/fsmissing/REPORT.md` | `audit-reports/viii-evidence-originals/fsmissing/REPORT.md` | INGESTED |
| `param-fix/REPORT.md` | `dc-warn/out/param-fix/REPORT.md` | `audit-reports/viii-evidence-originals/param-fix/REPORT.md` | INGESTED |
| `runner-integrity-xcheck/REVIEW.md` | `dc-warn/out/runner-integrity-xcheck/REVIEW.md` | `audit-reports/viii-top-level-evidence/evidence.tar.gz` member `runner-integrity-xcheck/REVIEW.md` | INGESTED |

## Ingestion gate

Each source was ingested only when **both** conditions held:

1. Source is byte-identical to its archive counterpart (`cmp` and `sha256sum -c`).
2. The source's `git hash-object` oid is **NOT** present in the product HEAD
   ls-tree blob set.

## Outcome

All three reports passed both conditions and were copied verbatim into this
directory. None of their git oids was present in the pre-intake product tree
at 33cb5d2d (rechecked at 5fc48fbb):

| Report | Source `git hash-object` oid |
|--------|------------------------------|
| `fsmissing/REPORT.md` | `4729f28dbde330c6312f95d5469b0a6bb562a44e` |
| `param-fix/REPORT.md` | `c8e98ef6c47f67fa21be8851b4645f0aa6707e7e` |
| `runner-integrity-xcheck/REVIEW.md` | `cb4b752e05d85965b1e9379b1137b89dc9983670` |

## Integrity

`SHA256SUMS` lists the sha256 of the three files in this directory. Verify with:

```
sha256sum -c SHA256SUMS
```

## Product HEAD note

The product repository is `boring/`, whose toplevel is
`/home/losses/Development/tq-workspace/boring` and whose HEAD is
`33cb5d2dd1139c90059678b8beecc8f3b45df34e`. The task-referenced product HEAD
`33cb5d2d` resolves in this repository, and this is the HEAD that was used for
the ls-tree blob set check.

> Correction note: an earlier revision of this README claimed `33cb5d2d` did not
> resolve and used root-repo HEAD `82a431ec…` for the gate check, wrongly marking
> `fsmissing/REPORT.md` and `param-fix/REPORT.md` as SKIPPED. The correct check
> against boring HEAD `33cb5d2d` shows all three source oids have zero hits, so
> all three reports are ingested verbatim.
