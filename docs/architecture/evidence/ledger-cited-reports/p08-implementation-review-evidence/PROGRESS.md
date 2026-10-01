# P08 IMPLEMENTATION review — progress

Role: second of the two separately-recorded P08 reviews (implementation, not behaviour).

- [x] Candidate PATCH.diff + REPORT.md read; PATCH.diff verified == actual diff of `boring-wt-architecture` → `swc-try-fix-wt/wt` (only `SwiftExpr.hx`; the only diff of the two trees outside out/node_modules/.git)
- [x] First (behaviour) review read in full; architecture consultations (SOL2, ASTRA) read for the three P08 obligations
- [x] Changed-site inventory with fact-source authority (9 hunks; each fact's producer and authority judged)
- [x] Obligation 2 measured myself, never through a pipe: acceptance gen rc=0 / swiftc rc=0, 0 diagnostics; gap gen rc=0 / swiftc rc=0, 0 errors + **2 warnings** → literal "zero diagnostics" NOT met
- [x] Reconstruction audit: 9 derivation sites enumerated; nilMergeChainNonOptional `" ?? "` parser instrumented → 0 invocations on both trees (8 generations) → left in place, not on P08's path
- [x] Behaviour-review blind spots, measured on host-local copies:
      - lambda/member return contract (execution-verified hole: PE.swift:33 still errors on the candidate)
      - `sw.t` derivation at switchBindingLines (instrumented sweep, 11 generations: no divergence observed)
      - read-only→mutable asymmetry reachability RULED OUT by Haxe typing (no `to Array<T>`)
      - SwiftDecl second planner entry: accepted initializer domain gated (switch/nil-merge statics rejected)
      - try-region tail shapes (TIf/switch/assignment) abort before the destination logic on BOTH trees
- [x] Obligation 3 on the acceptance fixture measured myself: native build rc=0/0 diagnostics; runtime output byte-identical to the Haxe oracle (30 lines)
- [x] Stale expectation reproduced (tracked test vs tracked oracle), NOT edited
- [x] Verdict + exact conditions
- [x] Evidence index + identity anchors
