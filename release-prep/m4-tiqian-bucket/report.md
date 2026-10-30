# M4 tiqian bucketing harness and repin automation

## Conclusion

The module bucketing skeleton works. Filtering the root classes by package,
generating one module in isolation, and checking the generated tests all
succeed on the org.tiqian.core bucket (177 tests pass). The .haxelib repin
automation is delivered as a one-command script that clears the stale boring
git copy, copies the needed files from a boring worktree, and repins
flake.nix.

## Bucketing smoke

Target: ts. Bucket: org.tiqian.core.

- Filtering: 17 roots selected (15 core test classes plus the two runtime
  types runtime.TestCore and runtime.UString).
- Generation: haxe exited 0 and emitted 20 test files under ts-gen-tests.
- Check: bun test ts-gen-tests ran 177 tests across 20 files, 177 pass,
  0 fail.

The harness points the boring compiler at the supplied worktree. The compiler
writes its semantic-pass-exceptions.json ledger under the checkout root, and
that root must stay writable. The repin script satisfies the same constraint
by copying boring into .haxelib/boring/git.

## Repin automation

repin.sh <boring-worktree> <tiqian-root> <rev> performs, in one command:

1. rm -rf .haxelib/boring/git.
2. Copies packages, samples, haxelib.json, defines.json, boring.json,
   flake.nix, and flake.lock from the boring worktree into the git copy.
3. Writes .boring-flake-revision so the devShell shellHook sees a fresh
   revision.
4. Rewrites the boring input URL in flake.nix to github:Losses/boring/<rev>.

The flake.lock update still requires nix flake lock --update-input boring
after the revision is pushed to github; the script prints that reminder.

## Scope note

The skeleton wires the ts target only. The same bucket roots feed the kotlin,
dart, and swift entries without change, but those entries are not exercised
here. Bucketing by Haxe construct is the next step and is not part of this
deliverable.
