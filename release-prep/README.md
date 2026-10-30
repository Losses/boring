# Release-Prep

Parallel pre-release work that does not depend on the Rust line. Three
independent deliverables, each with its own scripts and report.

- p4-registry/: registry availability smoke for the boring dependency
  pull/install path.
- p5-pack/: boring pack dry run (package contents plus local install),
  no real publish.
- m4-tiqian-bucket/: tiqian M4 bucketed gen/check harness skeleton and
  the .haxelib repin one-command automation.

Each directory holds a report.md with the conclusion, the evidence, and
the blocking list for that deliverable. Nothing here publishes a package or
merges to master. Those steps wait for the tech lead to sign off.
