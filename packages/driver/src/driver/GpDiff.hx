package driver;

/** GP-DIFF: byte-identical baseline comparison for target bundles.

    Three phases, each parallelised by one bash invocation with &+wait so
    Haxe targets compile concurrently and never block the runner. **/
class GpDiff {
    static var project:Project;
    static var tempRoot:String;

    public static function run(p:Project, targetIds:Array<String>, baseRev:String):Int {
        project = p;
        final bundles = selectBundles(p, targetIds);

        final sha = resolveBase(project.root, baseRev);
        final cacheRoot = Host.resolve(project.root, "out/.gp-cache");
        final shaDir = Host.join(cacheRoot, sha);
        tempRoot = Host.join(cacheRoot, ".tmp");
        Host.makeDirs(tempRoot);

        Host.outputLine("GP-DIFF  base=" + baseRev + "  sha=" + sha);
        Host.outputLine("         cache=" + cacheRoot);
        Host.outputLine("         targets=[" + bundles.map(b -> b.id).join(", ") + "]");

        final missing:Array<BundleSpec> = [];
        for (b in bundles) if (!cacheComplete(shaDir, b.id)) missing.push(b);

        if (missing.length > 0) {
            Host.outputLine("  baseline: cache miss [" + missing.map(b -> b.id).join(", ") + "]");
            populateBaselines(sha, shaDir, missing);
            Host.outputLine("  baseline: done");
        } else {
            Host.outputLine("  baseline: all cached, skip regeneration");
        }

        regenerateCurrent(bundles);

        final diffs = diffAll(shaDir, bundles);
        writeStatus(cacheRoot, sha, shaDir, bundles, diffs, missing.map(b -> b.id));

        var failures = 0;
        for (d in diffs) if (d.code != 0) failures++;
        Host.outputLine(failures == 0
            ? "GP-DIFF: all targets byte-identical"
            : "GP-DIFF: " + Std.string(failures) + " target(s) differ");
        return failures == 0 ? 0 : 1;
    }

    static function fail(message:String):Void {
        Host.outputLine("gp-diff: " + message);
        Host.exit(1);
    }

    static function selectBundles(p:Project, ids:Array<String>):Array<BundleSpec> {
        final out:Array<BundleSpec> = [];
        for (id in ids) {
            var found:BundleSpec = null;
            for (b in p.bundles) if (b.id == id) { found = b; break; }
            if (found == null)
                fail("unknown bundle \"" + id + "\"; known: " + p.bundles.map(b -> b.id).join(", "));
            out.push(found);
        }
        return out;
    }

    static function resolveBase(root:String, rev:String):String {
        final r = Host.run("git", ["-C", root, "rev-parse", "--verify", rev + "^{commit}"], root, []);
        if (r.code != 0) fail("cannot resolve base \"" + rev + "\" in " + root + ": " + r.output);
        return StringTools.trim(r.output);
    }

    static function cacheComplete(shaDir:String, targetId:String):Bool {
        return Host.exists(Host.join(Host.join(shaDir, targetId), ".gp-cached"));
    }

    // ---- 1. baseline --------------------------------------------------------

    static var baselineScript = 'set -u
ROOT="$1" SHA="$2" CACHEDIR="$3"
shift 3
SRC="$$CACHEDIR/.tmp/gp-base-src"
rm -rf "$$SRC"
mkdir -p "$$SRC"
git -C "$$ROOT" archive "$$SHA" | tar -x -C "$$SRC"
[ -f "$$SRC/boring.json" ] || { echo "gp-diff baseline: tree extract failed" >&2; exit 1; }
HB="$$SRC/.haxelib"
rm -rf "$$HB"
cp -r "$$ROOT/.haxelib" "$$HB"
printf "%s" "$$SRC" > "$$HB/boring/.dev"
for T in "$$@"; do
  ( START=$$(date +%s%3N); cd "$$SRC" && HAXELIB_PATH="$$HB" haxe "examples/$$T.hxml" >"$$CACHEDIR/.tmp/gp-base-$$T.log" 2>&1; RC=$$?; END=$$(date +%s%3N); echo "$$RC" > "$$CACHEDIR/.tmp/gp-base-$$T.rc"; echo "$$START $$END $$((END-START))" > "$$CACHEDIR/.tmp/gp-base-$$T.times" ) &
done
wait
for T in "$$@"; do
  rc=$$(cat "$$CACHEDIR/.tmp/gp-base-$$T.rc")
  if [ "$$rc" = "0" ]; then
    rm -rf "$$CACHEDIR/$$T"
    mkdir -p "$$CACHEDIR/$$T"
    cp -r "$$SRC/reference/$$T/." "$$CACHEDIR/$$T/"
    find "$$CACHEDIR/$$T" -name "*.emit-origin.json" -exec sed -i "s|$$SRC|$$ROOT|g" {} +
    date +%s%3N > "$$CACHEDIR/$$T/.gp-cached"
  fi
done
';

    static function populateBaselines(sha:String, shaDir:String, bundles:Array<BundleSpec>):Void {
        final args:Array<String> = ["-c", baselineScript, "gp-diff-baseline",
            project.root, sha, shaDir];
        for (b in bundles) args.push(b.id);

        final r = Host.run("bash", args, project.root, []);
        if (r.code != 0) {
            var failed:Array<String> = [];
            for (b in bundles) {
                final rcFile = Host.join(Host.join(shaDir, ".tmp"), "gp-base-" + b.id + ".rc");
                if (!Host.exists(rcFile)) { failed.push(b.id + ": no rc file"); continue; }
                final rc = StringTools.trim(Host.readText(rcFile));
                if (rc != "0") failed.push(b.id + ": rc=" + rc);
            }
            if (failed.length > 0)
                fail("baseline generation failed:\n  " + failed.join("\n  "));
            fail("baseline script rc=" + Std.string(r.code) + "\n" + r.output);
        }

        for (b in bundles) {
            final genDir = Host.join(Host.join(shaDir, b.id), "gen");
            if (!Host.exists(genDir))
                fail("baseline target \"" + b.id + "\" produced no gen dir");
        }
    }

    // ---- 2. regenerate current ----------------------------------------------

    static var currentScript = 'set -u
ROOT="$$1"
shift
for T in "$$@"; do
  ( START=$$(date +%s%3N); cd "$$ROOT" && haxe "examples/$$T.hxml" >"$$ROOT/out/.gp-cache/.tmp/gp-curr-$$T.log" 2>&1; RC=$$?; END=$$(date +%s%3N); echo "$$RC" > "$$ROOT/out/.gp-cache/.tmp/gp-curr-$$T.rc"; echo "$$START $$END $$((END-START))" > "$$ROOT/out/.gp-cache/.tmp/gp-curr-$$T.times" ) &
done
wait
exit 0
';

    static function regenerateCurrent(bundles:Array<BundleSpec>):Void {
        Host.outputLine("  current: regenerating...");
        final args:Array<String> = ["-c", currentScript, "gp-diff-current", project.root];
        for (b in bundles) args.push(b.id);

        final r = Host.run("bash", args, project.root, []);
        if (r.code != 0) {
            var failed:Array<String> = [];
            for (b in bundles) {
                final rcFile = Host.join(tempRoot, "gp-curr-" + b.id + ".rc");
                if (!Host.exists(rcFile)) continue;
                final rc = StringTools.trim(Host.readText(rcFile));
                if (rc != "0") failed.push(b.id + ": rc=" + rc);
            }
            if (failed.length > 0)
                fail("current regeneration failed:\n  " + failed.join("\n  "));
            fail("current regeneration script rc=" + Std.string(r.code) + "\n" + r.output);
        }
        Host.outputLine("  current: done");
    }

    // ---- 3. diff ------------------------------------------------------------

    static var diffScript = 'set -u
CACHEDIR="$$1" ROOT="$$2"
shift 2
for T in "$$@"; do
  (
    rc=0
    : > "$$ROOT/out/.gp-cache/.tmp/gp-diff-$$T.txt"
    for SUB in gen gen-tests; do
      A="$$CACHEDIR/$$T/$$SUB"
      B="$$ROOT/reference/$$T/$$SUB"
      [ -e "$$A" ] || [ -e "$$B" ] || continue
      diff -r "$$A" "$$B" >>"$$ROOT/out/.gp-cache/.tmp/gp-diff-$$T.txt" 2>&1
      r=$$?
      [ "$$r" -eq 0 ] || rc=$$r
    done
    echo $$rc > "$$ROOT/out/.gp-cache/.tmp/gp-diff-$$T.rc"
  ) &
done
wait
exit 0
';

    static function diffAll(shaDir:String, bundles:Array<BundleSpec>):Array<DiffResult> {
        Host.outputLine("  diff: comparing...");
        final args:Array<String> = ["-c", diffScript, "gp-diff-diff", shaDir, project.root];
        for (b in bundles) args.push(b.id);

        Host.run("bash", args, project.root, []);

        final out:Array<DiffResult> = [];
        for (b in bundles) {
            final rcFile = Host.join(tempRoot, "gp-diff-" + b.id + ".rc");
            final txtFile = Host.join(tempRoot, "gp-diff-" + b.id + ".txt");
            final rc = Host.exists(rcFile) ? Std.parseInt(StringTools.trim(Host.readText(rcFile))) : -1;
            final text = Host.exists(txtFile) ? Host.readText(txtFile) : "";
            out.push({id: b.id, code: rc, diff: text});
        }
        return out;
    }

    // ---- 4. status ----------------------------------------------------------

    static function writeStatus(cacheRoot:String, sha:String, shaDir:String, bundles:Array<BundleSpec>, diffs:Array<DiffResult>, generatedIds:Array<String>):Void {
        final statusPath = Host.join(cacheRoot, "status.tsv");
        var buf = new StringBuf();
        buf.add("stage\tstatus\ttarget\texit\tdetail\n");

        for (b in bundles) {
            if (generatedIds.indexOf(b.id) < 0) {
                final marker = Host.join(Host.join(shaDir, b.id), ".gp-cached");
                final cachedAt = Host.exists(marker) ? StringTools.trim(Host.readText(marker)) : "?";
                buf.add("gp-diff:" + b.id + ":baseline\tcached\t" + b.id + "\t0\tcachedAt=" + cachedAt + " haxe=0 sha=" + sha + "\n");
            } else {
                final times = readTimes(Host.join(Host.join(shaDir, ".tmp"), "gp-base-" + b.id + ".times"));
                buf.add("gp-diff:" + b.id + ":baseline\tgenerated\t" + b.id + "\t0\thaxe=1 " + times + " sha=" + sha + "\n");
            }
        }

        for (b in bundles) {
            final times = readTimes(Host.join(tempRoot, "gp-curr-" + b.id + ".times"));
            buf.add("gp-diff:" + b.id + ":current\tok\t" + b.id + "\t0\thaxe=1 " + times + "\n");
        }

        for (d in diffs)
            buf.add("gp-diff:" + d.id + ":diff\t" + (d.code == 0 ? "ok" : "fail") + "\t" + d.id + "\t" + Std.string(d.code) + "\t" + (d.code == 0 ? "identical" : "diff") + "\n");

        Host.writeText(statusPath, buf.toString());

        final summaryPath = Host.join(cacheRoot, "summary.txt");
        var sum = new StringBuf();
        sum.add("GP-DIFF  base=" + sha + "\n");
        sum.add("targets=[" + bundles.map(b -> b.id).join(", ") + "]\n\n");
        for (d in diffs) {
            sum.add(d.id + ": ");
            sum.add(d.code == 0
                ? "IDENTICAL\n"
                : (d.code == 1
                    ? "DIFFER\n" + d.diff + "\n"
                    : "ERROR rc=" + Std.string(d.code) + "\n" + d.diff + "\n"));
        }
        Host.writeText(summaryPath, sum.toString());
    }

    static function readTimes(path:String):String {
        if (!Host.exists(path)) return "start=? end=?";
        final parts = StringTools.trim(Host.readText(path)).split(" ");
        if (parts.length < 3) return "start=? end=?";
        return "start=" + parts[0] + " end=" + parts[1] + " durMs=" + parts[2];
    }
}

typedef DiffResult = {
    id:String,
    code:Int,
    diff:String,
};
