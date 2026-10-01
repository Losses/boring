LOG=/home/losses/Development/tq-workspace/dc-warn/out/e2e-run/evidence/collected-suite.log
test -f "$LOG" || { echo "::error::no log at $LOG - the collected suite never ran"; exit 1; }
# Warning extraction: the standard (02-translator-implementation-standard.md:80)
# counts the warning lines in the target suite output that name files
# under the generated trees, and requires that count to be zero. A
# warning line is a line carrying a compiler/translator warning that
# names a path under `reference/*/gen` or `reference/*/gen-tests`.
WARN_FILE=$(mktemp)
grep -iE 'warn' "$LOG" | grep -E 'reference/[a-z0-9-]+/gen(-tests)?/' > "$WARN_FILE" || true
WARN_COUNT=$(wc -l < "$WARN_FILE")
# Gate baseline, measured not invented: the recorded proof run
# (`docs/architecture/BASELINE-FAILURES.md`, revision 695940e8,
# raw log dc-warn/out/ci-wire/evidence/recorded-baseline-proof-run.log)
# contains 0 warning lines naming files under the generated trees.
EXPECTED_GENERATED_TREE_WARNINGS=0
case "$WARN_COUNT" in
  ''|*[!0-9]*) echo "::error::warning count is not a parseable integer (got '$WARN_COUNT') - the gate cannot be evaluated"; exit 1 ;;
esac
{
  echo '## Collected suite - contract 3 count'
  echo
  echo 'Standard: `docs/specs/style/02-translator-implementation-standard.md:80` counts the'
  echo 'warning lines naming files under the generated trees and requires the count to be zero.'
  echo
  echo '```'
  grep -E '^ [0-9]+ (pass|fail)$|^ [0-9]+ errors$|^Ran [0-9]+ tests across [0-9]+ files' "$LOG" || echo '(no summary line: the run did not reach a summary)'
  echo '```'
  echo
  echo 'Collected domain (top-level directories - the count means nothing without it):'
  echo
  echo '```'
  grep -oE '^[^ (]+\.test\.ts:' "$LOG" | sed 's/:$//' | sed 's|^\([^/]*/[^/]*\)/.*|\1|' | sort | uniq -c | sort -rn || true
  echo '```'
  echo
  echo 'Warning lines naming files under the generated trees'
  echo '(`reference/*/gen` and `reference/*/gen-tests` - the count means nothing without the domain):'
  echo
  echo "Generated-tree warning line count: **$WARN_COUNT**"
  echo
  if [ "$WARN_COUNT" -gt 0 ]; then
    echo '```'
    if [ "$WARN_COUNT" -gt 50 ]; then
      head -50 "$WARN_FILE"
      echo "... ($((WARN_COUNT - 50)) more line(s) truncated)"
    else
      cat "$WARN_FILE"
    fi
    echo '```'
    echo
  fi
  echo 'Baseline reconciliation: the inherited baseline'
  echo '(`docs/architecture/BASELINE-FAILURES.md`) recorded 1001 pass / 32 fail / 8 errors and **no'
  echo 'warning count**. That gap is now closed by measurement, not by invention: the retained raw'
  echo 'log of the recorded proof run (revision `695940e8`,'
  echo '`dc-warn/out/ci-wire/evidence/recorded-baseline-proof-run.log`) contains'
  echo "**$EXPECTED_GENERATED_TREE_WARNINGS** warning lines naming files under the generated trees,"
  echo 'and that measured number is the gate baseline recorded in'
  echo '`docs/architecture/BASELINE-FAILURES.md`. The standard'
  echo '(`02-translator-implementation-standard.md:80`) independently requires the count to be'
  echo 'zero; this step fails on any deviation from the baseline. Exceeding it is an acceptance'
  echo 'failure; a new baseline number must be measured and recorded, never assumed.'
  echo
  echo 'Baseline: `docs/architecture/BASELINE-FAILURES.md` (recorded per'
  echo '`docs/architecture-work-plan.md:417`; a baseline finding does not waive the standard).'
} | tee -a "$GITHUB_STEP_SUMMARY"
# ---- failure attribution -------------------------------------------------
# What a reader could NOT do before: this step reported one `fail` number
# plus the run's own error text (and, from 99ba67fd, the warning count).
# `32 fail` did not say whether a red run was real assertion failures, a
# machine timeout with its bun "Unhandled error between tests" cascade, or
# the pre-existing npm-artifact byte-identity flake - all three render as
# `(fail) ...` plus an `error: expect(...)` block, so they were
# indistinguishable without re-running. The three crafted-log runs and the
# six negative controls that prove this discriminates are retained at
# dc-warn/out/ci-attribution/ (REPORT.md, evidence/). Attribution below is
# not a waiver: every class is still a failure, the run is still red, and
# the gate conditions at the end of this step are unchanged.
ATTR_SAMPLE=5
ATTR_RECAP=$(mktemp)
ATTR_BODY=$(mktemp)   # the log with the "Unhandled error" cascade blocks cut out
ATTR_TSV=$(mktemp)
ATTR_CASC=$(mktemp)
awk '/^[0-9]+ tests failed:$/{f=1;next} f && /^ [0-9]+ (pass|fail|skip)$/{exit} f' "$LOG" > "$ATTR_RECAP"
# A cascade is `# Unhandled error between tests` / --- / text / --- . It must
# not be mined for assertion text: bun re-prints the aborted test's
# expectation there, which is exactly what makes it look like a product
# failure. The closing rule is the second `---` line, but a structural line
# also closes the block, so a malformed cascade cannot hide the rest of
# the log (which would hide the byte-diff shape from the check below).
awk '
  /^# Unhandled error between tests$/ {s=1; d=0; next}
  s && /^-{20,}$/ { if (++d>=2) s=0; next }
  s && /^(tests\/|reference\/|packages\/|\(pass\) |\(fail\) |# )/ {s=0}
  !s {print}
' "$LOG" > "$ATTR_BODY"
ATTR_RECAP_N=$(grep -cE '^\(fail\) ' "$ATTR_RECAP" || true)
if [ "$ATTR_RECAP_N" -gt 0 ]; then
  ATTR_SRC_NAME="the 'N tests failed:' recap (bun's authoritative, deduplicated list)"
else
  # No recap (a crash before the recap, or a green run): fall back to the
  # inline body, deduplicated by test id because bun prints a failure
  # inline and again in the recap when both exist. The dedup must carry the
  # marker line through: the classifier reads the timeout marker from the
  # line AFTER the (fail) line, so emitting the (fail) line alone would
  # silently reclassify every timeout as an assertion.
  awk '{L[NR]=$0}
    END{for(i=1;i<=NR;i++){
      if (L[i] !~ /^\(fail\) /) continue;
      if (seen[L[i]]++) continue;
      print L[i];
      if (L[i+1] ~ /^  \^ this test timed out after [0-9]+ms\.$/) print L[i+1];
    }}' \
    "$ATTR_BODY" > "$ATTR_RECAP"
  ATTR_SRC_NAME="the inline run body, deduplicated by test id (no 'N tests failed:' recap in this log)"
  ATTR_RECAP_N=$(grep -cE '^\(fail\) ' "$ATTR_RECAP" || true)
fi
ATTR_SUMMARY_FAIL=$(grep -E '^ [0-9]+ fail$' "$LOG" | tail -1 | grep -oE '[0-9]+' || true)
case "$ATTR_SUMMARY_FAIL" in ''|*[!0-9]*) ATTR_SUMMARY_FAIL="" ;; esac

# Class 3, the known flake, is identified by test identity AND shape. The
# identity alone is deliberately NOT enough: if that test ever fails for a
# different reason (its own compiler exit-code assertion
# `expect(a.exitCode).toBe(0)`, or its own 420 s budget), calling it "the
# flake" would be the waiver the ruling forbids. The shape is the binary
# diff bun 1.3.13 renders for `expect(Buffer).toEqual(Buffer)`, produced by
# the byte-identity assertion
# `expect(fs.readFileSync(second)).toEqual(fs.readFileSync(first))` - and it
# is looked for only outside cascade blocks. The rule matches test names and
# assertion text, never line numbers: this test file's numbering has already
# moved once (the byte-identity test sat at :333 before the tracked-fixture
# repair 2aadcb69 and at :320 after it), so a line-anchored rule would break
# silently.
ATTR_FLAKE_ID='package artifact emission > two generations of the same inputs produce byte-identical artifacts'
ATTR_FLAKE_FILE='tests/ts/package-artifacts.test.ts'
# Two flags, deliberately of different width:
#   ATTR_BUFFER_DIFF - a binary toEqual diff anywhere in the log (outside the
#                      cascades): worth surfacing, but NOT the flake class.
#   ATTR_FLAKE_SHAPE - that diff AT the artifact byte-identity assertion, i.e.
#                      the one shape the known flake produces. Only this one
#                      may classify a failure as the flake.
ATTR_BUFFER_DIFF=0
ATTR_FLAKE_SHAPE=0
if grep -qE '^error: expect\(received\)\.toEqual\(expected\)$' "$ATTR_BODY" &&
   grep -q '"type": "Buffer"' "$ATTR_BODY"; then
  ATTR_BUFFER_DIFF=1
  if grep -qE '^ *at <anonymous> \(.*/tests/ts/package-artifacts\.test\.ts:' "$ATTR_BODY"; then
    ATTR_FLAKE_SHAPE=1
  fi
fi
# `- Expected  - N` / `+ Received  + M` are rendered diff LINES, not bytes;
# they are reported under that name, never as a byte count.
ATTR_FLAKE_DIFF=$(grep -E '^[-+] (Expected|Received)  [-+] [0-9]+$' "$ATTR_BODY" | tr '\n' ' ' || true)

awk -v fid="$ATTR_FLAKE_ID" -v shape="$ATTR_FLAKE_SHAPE" '
  {L[NR]=$0}
  END{
    for(i=1;i<=NR;i++){
      if (L[i] !~ /^\(fail\) /) continue;
      id=substr(L[i],8); sub(/ \[[0-9.]*ms\]$/,"",id);
      if (L[i+1] ~ /^  \^ this test timed out after [0-9]+ms\.$/) print "timeout\t" id;
      else if (shape==1 && index(id,fid)>0) print "flake-npm-artifact\t" id;
      else print "assertion\t" id;
    }
  }' "$ATTR_RECAP" > "$ATTR_TSV"

# Cascades are attributed by file scope: a cascade in a file section that
# already carried a `timed out after` marker is the timeout's own debris. One
# in a file with no timeout goes to the unattributed class, so it stays visible
# and cannot be dismissed.
awk '
  /^[^ (]+\.test\.ts:$/ {file=$0; to=0}
  /^  \^ this test timed out after [0-9]+ms\.$/ {to=1}
  /^# Unhandled error between tests$/ {
    if (to) print "timeout-cascade\t" file; else print "unattributed-error\t" file
  }' "$LOG" > "$ATTR_CASC"

ATTR_ASSERT_N=$(grep -c '^assertion' "$ATTR_TSV" || true)
ATTR_TIMEOUT_N=$(grep -c '^timeout' "$ATTR_TSV" || true)
ATTR_FLAKE_N=$(grep -c '^flake-npm-artifact' "$ATTR_TSV" || true)
ATTR_CASC_T_N=$(grep -c '^timeout-cascade' "$ATTR_CASC" || true)
ATTR_CASC_U_N=$(grep -c '^unattributed-error' "$ATTR_CASC" || true)
ATTR_ATTRIBUTED=$((ATTR_ASSERT_N + ATTR_TIMEOUT_N + ATTR_FLAKE_N))
if [ -n "$ATTR_SUMMARY_FAIL" ]; then
  ATTR_RESIDUAL=$((ATTR_SUMMARY_FAIL - ATTR_ATTRIBUTED))
else
  ATTR_RESIDUAL="unknown"
fi

{
  echo '## Failure attribution (why this run is red)'
  echo
  echo "Source: $ATTR_SRC_NAME."
  echo 'A failure is one `(fail)` line; the summary line ` N fail` is the total this must add up to.'
  echo
  echo '| class | count | what it means |'
  echo '|---|---:|---|'
  echo "| real assertion failure | $ATTR_ASSERT_N | a test ran and its expectation failed - product or spec |"
  echo "| environment / timeout | $ATTR_TIMEOUT_N | carries \`this test timed out after Nms\` - a machine result, from contention |"
  echo "| npm-artifact non-determinism | $ATTR_FLAKE_N | the byte-identity test's Buffer diff - known unrelated to the change under review |"
  echo "| timeout cascade | $ATTR_CASC_T_N | \`Unhandled error between tests\` after a kill in the same file - the timeout's debris |"
  echo "| unattributed error | $ATTR_CASC_U_N | a cascade in a file with no timeout marker; NOT excused, reported as unattributed |"
  echo
  echo 'Attribution is not waiver: every class above is still a failing test and this job is still red on'
  echo 'any of them. Nothing here converts a failure into a pass, and no gate below is relaxed.'
  echo
  if [ "$ATTR_ASSERT_N" -gt 0 ]; then
    echo "**Real assertion failures** - $ATTR_ASSERT_N (sample, bounded at $ATTR_SAMPLE):"
    echo
    echo '```'
    grep '^assertion' "$ATTR_TSV" | cut -f2- | head -"$ATTR_SAMPLE"
    if [ "$ATTR_ASSERT_N" -gt "$ATTR_SAMPLE" ]; then echo "... ($((ATTR_ASSERT_N - ATTR_SAMPLE)) more truncated)"; fi
    echo '```'
    echo
  fi
  if [ "$ATTR_TIMEOUT_N" -gt 0 ]; then
    echo "**Environment / timeout failures** - $ATTR_TIMEOUT_N (sample, bounded at $ATTR_SAMPLE):"
    echo
    echo '```'
    grep '^timeout' "$ATTR_TSV" | cut -f2- | head -"$ATTR_SAMPLE"
    if [ "$ATTR_TIMEOUT_N" -gt "$ATTR_SAMPLE" ]; then echo "... ($((ATTR_TIMEOUT_N - ATTR_SAMPLE)) more truncated)"; fi
    echo '```'
    echo
  fi
  if [ "$ATTR_FLAKE_N" -gt 0 ]; then
    echo "**npm-artifact non-determinism (known flake)** - $ATTR_FLAKE_N (sample, bounded at $ATTR_SAMPLE):"
    echo
    echo '```'
    grep '^flake-npm-artifact' "$ATTR_TSV" | cut -f2- | head -"$ATTR_SAMPLE"
    echo '```'
    echo
    echo "Matched on test identity \`$ATTR_FLAKE_ID\` **and** the binary-diff shape"
    echo "(\`expect(received).toEqual(expected)\` over \`\"type\": \"Buffer\"\` at \`$ATTR_FLAKE_FILE\`)."
    echo "Rendered diff lines: $ATTR_FLAKE_DIFF"
    echo
    echo 'This is the pre-existing npm-artifact non-determinism the round-5 ruling names'
    echo '(`docs/architecture/MANAGEMENT-RULING-005.md`, restoration condition 3). It is unrelated'
    echo 'to the change under review - which is exactly why it is labelled here, so it cannot be'
    echo 'left to look like a product failure. It is **reported, not excused**: the suite step'
    echo 'above is still red on it.'
    echo
  elif [ "$ATTR_BUFFER_DIFF" = 1 ]; then
    echo 'A binary `expect(...).toEqual(...)` diff over a `"type": "Buffer"` payload is present'
    echo 'in this log, but not at the artifact byte-identity assertion, so it is **not** counted'
    echo 'as the known artifact flake. It is counted in the assertion class above and must be'
    echo 'investigated on its own merits - a byte diff elsewhere is not automatically the flake.'
    echo
  fi
  if [ "$ATTR_CASC_T_N" -gt 0 ]; then
    echo "**Timeout cascades** - $ATTR_CASC_T_N (sample, bounded at $ATTR_SAMPLE):"
    echo
    echo '```'
    grep '^timeout-cascade' "$ATTR_CASC" | cut -f2- | head -"$ATTR_SAMPLE"
    if [ "$ATTR_CASC_T_N" -gt "$ATTR_SAMPLE" ]; then echo "... ($((ATTR_CASC_T_N - ATTR_SAMPLE)) more truncated)"; fi
    echo '```'
    echo
  fi
  if [ "$ATTR_CASC_U_N" -gt 0 ]; then
    echo "**Unattributed errors** - $ATTR_CASC_U_N (sample, bounded at $ATTR_SAMPLE):"
    echo
    echo '```'
    grep '^unattributed-error' "$ATTR_CASC" | cut -f2- | head -"$ATTR_SAMPLE"
    echo '```'
    echo
  fi
  if [ -n "$ATTR_SUMMARY_FAIL" ]; then
    echo "Reconciliation: $ATTR_ATTRIBUTED failed test(s) attributed against the summary line's"
    echo "\`$ATTR_SUMMARY_FAIL fail\`; residual $ATTR_RESIDUAL. A non-zero residual means the log's"
    echo 'failure text is not fully classified by these rules - say so, never round it away.'
  else
    echo "Reconciliation: $ATTR_ATTRIBUTED failed test(s) attributed, but this log carries no"
    echo 'parseable ` N fail` summary line, so there is no total to reconcile against - the'
    echo 'residual is recorded as unknown, never as zero.'
  fi
  echo
  echo 'Limits of these rules, recorded openly: the timeout class needs the literal'
  echo '`this test timed out after Nms` marker, so a test the runner kills without that marker'
  echo 'counts as an `assertion`; the cascade rule needs the file-scope association bun does not'
  echo 'print itself; and a cascade in a file with no timeout is deliberately left unattributed.'
  echo 'Classifying a log is not running the suite - these counts describe this log only.'
} | tee -a "$GITHUB_STEP_SUMMARY"
if [ "$ATTR_RESIDUAL" != "0" ] && [ "$ATTR_RESIDUAL" != "unknown" ]; then
  echo "::warning::$ATTR_ATTRIBUTED of $ATTR_SUMMARY_FAIL failing test(s) were classified; residual $ATTR_RESIDUAL is unattributed - the log's failure text is not fully covered by the classification rules (this does not change the gate, and it does not excuse the residual)"
fi
if [ "$ATTR_SUMMARY_FAIL" = "" ]; then
  echo "::warning::the suite output carries no parseable ' N fail' summary line - the attribution counts above cannot be reconciled against a total (the gate below is unaffected: it turns on the warning count)"
fi
rm -f "$ATTR_RECAP" "$ATTR_BODY" "$ATTR_TSV" "$ATTR_CASC"
# Warning gate: the count is compared against the measured baseline
# (0, from the recorded proof run at 695940e8 - see
# docs/architecture/BASELINE-FAILURES.md). Missing log, an
# unparseable count, or any deviation from the baseline fails the
# step; exceeding the baseline is the acceptance failure the
# standard names, and a new baseline requires its own measured
# record, not a quiet threshold bump. The retained full-suite log
# contains zero such lines, so this gate is green on the recorded
# run - a red here is a real acceptance failure.
if [ "$WARN_COUNT" -ne "$EXPECTED_GENERATED_TREE_WARNINGS" ]; then
  echo "::error::$WARN_COUNT warning line(s) in the suite output name files under the generated trees, baseline is $EXPECTED_GENERATED_TREE_WARNINGS - acceptance failure under docs/specs/style/02-translator-implementation-standard.md:80 (a new baseline must be measured and recorded, not assumed)"
  exit 1
fi
# Domain guard: the generated out/ tree must never be swept into the
# count. If it is, the count was taken over a different domain than
# the recorded baseline and must not be read as one.
# Reachability, recorded honestly: this guard is currently
# structurally unreachable. `bunfig.toml` is tracked and sets
# `[test] pathIgnorePatterns = ["out/**"]`, so `out/**` is never
# collected and the log cannot contain an `out/` collection line;
# and if `bunfig.toml` were removed, collection dies before emitting
# any `out/` line at all (see `docs/architecture/BASELINE-FAILURES.md`).
# It is kept as defense in depth against both protections drifting,
# not as an exercised check.
if grep -qE '^out/.*\.test\.ts:' "$LOG"; then
  echo "::error::the collected domain contains files under out/ - the generated tree is being swept into the count"
  exit 1
fi
