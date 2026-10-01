#!/usr/bin/env bash
set -e
GREEN=/home/losses/Development/tq-workspace/dc-warn/out/e2e-run/evidence/collected-suite.log
BUFLOG=/home/losses/Development/tq-workspace/dc-warn/out/ci-attribution/scratch/bufshape.log
REPO=/home/losses/Development/tq-workspace/boring-wt-architecture
FID="package artifact emission > two generations of the same inputs produce byte-identical artifacts"
OUT=/tmp/flake-synth/variants
mkdir -p $OUT
PPASS='(pass) '$FID' [358384.89ms]'
F3ID='tests.CloneDeriveGapTests.resolve: data class holding a plain-class field derives Clone and reads owned values'

# V0: unmodified green log
cp "$GREEN" "$OUT/v0-baseline-SYNTHETIC-baseline-copy.log"

# V1: flake-shaped failure at the byte-identity assertion
awk -v fid="$FID" '
  BEGIN{bufcmd="cat /tmp/flake-synth/bufdiff-body.txt"}
  {
    if ($0 == "(pass) " fid " [358384.89ms]") {
      print "336 |         expect(b.stderr).toBe(\"\");";
      print "337 |         expect(b.exitCode).toBe(0);";
      print "338 |         expect(fs.readFileSync(path.join(second, pkg.file))).toEqual(fs.readFileSync(path.join(first, pkg.file)));";
      print "            ^";
      while ((getline line < "/tmp/flake-synth/bufdiff-body.txt") > 0) print line;
      close("/tmp/flake-synth/bufdiff-body.txt");
      print "";
      print "      at <anonymous> ($REPO/tests/ts/package-artifacts.test.ts:338:58)";
      print "(fail) " fid " [358384.89ms]";
      next;
    }
    if ($0 == " 1035 pass") { print " 1034 pass"; recap=1; print "1 tests failed:"; print "(fail) " fid " [358384.89ms]"; next }
    if ($0 == " 0 fail") { print " 1 fail"; next }
    print;
  }' "$GREEN" > "$OUT/v1-flake-SYNTHETIC-injected-byte-identity-buffer-diff.log"

# V2: same test id, failing for another reason (its own exit-code assertion)
awk -v fid="$FID" '
  {
    if ($0 == "(pass) " fid " [358384.89ms]") {
      print "332 |         const a = await runHaxe(`package-artifacts-id-a.hxml`, rewriteHxml(pkg.hxml, first, pkg.extra));";
      print "333 |         expect(a.stderr).toBe(\"\");";
      print "334 |         expect(a.exitCode).toBe(0);";
      print "                     ^";
      print "error: expect(received).toBe(expected)";
      print "";
      print "Expected: 0";
      print "Received: 1";
      print "";
      print "      at <anonymous> ($REPO/tests/ts/package-artifacts.test.ts:334:27)";
      print "(fail) " fid " [358384.89ms]";
      next;
    }
    if ($0 == " 1035 pass") { print " 1034 pass"; print "1 tests failed:"; print "(fail) " fid " [358384.89ms]"; next }
    if ($0 == " 0 fail") { print " 1 fail"; next }
    print;
  }' "$GREEN" > "$OUT/v2-same-id-exit-code-SYNTHETIC-not-the-flake.log"

# V3: Buffer diff in an unrelated gen-test file
awk -v f3id="$F3ID" '
  {
    if ($0 == "(pass) " f3id) {
      print "9 |    Test.run(\"tests.CloneDeriveGapTests.resolve\", \"tests.CloneDeriveGapTests.resolve: data class holding a plain-class field derives Clone and reads owned values\", () => {";
      print "10 |        Test.equals(\"1..3:x\", CloneDeriveGapOps.resolve([new CloneDeriveResult(new CloneDeriveRange(1, 3), \"x\")]), null);";
      print "            ^";
      while ((getline line < "/tmp/flake-synth/bufdiff-body.txt") > 0) print line;
      close("/tmp/flake-synth/bufdiff-body.txt");
      print "";
      print "      at <anonymous> ($REPO/reference/ts/gen-tests/tests/CloneDeriveGapTests.test.ts:10:8)";
      print "(fail) " f3id " [2.00ms]";
      next;
    }
    if ($0 == " 1035 pass") { print " 1034 pass"; print "1 tests failed:"; print "(fail) " f3id " [2.00ms]"; next }
    if ($0 == " 0 fail") { print " 1 fail"; next }
    print;
  }' "$GREEN" > "$OUT/v3-other-file-buffer-diff-SYNTHETIC-not-the-flake.log"

# V4: like V1 but the summary line says 2 fail against 1 recap entry -> residual 1
sed -e 's/^ 1034 pass$/ 1034 pass/' "$OUT/v1-flake-SYNTHETIC-injected-byte-identity-buffer-diff.log"   | awk '{ if ($0 == " 1 fail") { print " 2 fail"; next } print }'   > "$OUT/v4-residual-SYNTHETIC-summary-2-vs-1.log"

echo "variants:"; ls -la $OUT
