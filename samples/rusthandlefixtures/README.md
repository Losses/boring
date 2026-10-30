# Rust handle-semantics fixture matrix (Executor-A)

Minimal Haxe reproducers reconstructed from the tiqian error sites, plus a
layered verification harness, per the Astra ruling section 4 (verification
loop). One construct per file; every fixture is independently boring-gen'd
to the Rust target and cargo-checked in its own crate.

## Constructs

| fixture | construct | tiqian error site |
|---|---|---|
| SelfRewrap | self-receiver | paragraph_layout_engine.rs:284-300 (self rewrap) |
| NewReceiver | new-receiver | fresh-object method receiver |
| OwnedParam | owned-param | line_adjustment_stage.rs:899 (owned handle copy) |
| BorrowedParam | borrowed-param | handle reused after a call |
| HandleFieldRead | field-read | line_adjustment_stage.rs:899 ((prep.borrow().input).clone()) |
| HandleFieldWrite | field-write | handle field assignment |
| ChainedCall | chained-call | width_independent_annotation_cache.rs:852/1442 |
| ReturnHandle | return-handle | function returns a handle |
| NullableHandle | nullable | Null<plain-class> |
| ClosureCapture | closure | closure captures a handle |
| InterfaceDispatch | interface-dispatch | interface method dispatch |
| StaticMutable | static-mutable | test_trace_recorder.rs (self -> static) |
| CollectionHandle | collection | Array<handle> iteration |
| AliasIdentity | alias-identity | Rc-clone identity, never a value copy |
| MultiFieldChain | multi-field-chain | E0382 attempt: line_adjustment_stage.rs:899 LayoutResult::new giant call (implicit handle copy across multi-field borrow chain) |
| HandleParamChain | param-chain | handle param drives multiple instance calls (mutate then read), borrowed per call |

## Run

From the repository root:

    bun tests/rust-handle-fixtures/harness.ts run --out samples/rusthandlefixtures/reports/baseline.jsonl

Output is jsonl, one record per fixture:

    {fixture, construct, compile, cargoErrors[], fingerprints[]}

Each fingerprint is '<error-category>|<rule>|<fixture>'; categories are rustc
E-codes (E0382, E0599, ...) plus the negative-golden categories below. The
diff BASE CUR subcommand classifies every fingerprint as new / disappeared /
unchanged. Error totals are never aggregated.

## Negative golden rules

The per-fixture generated code (the rusthandlefixtures/ module only, never
the shared runtime) must stay free of:

1. Rc::new(RefCell::new(self.clone())) (self rewrap)
2. Send + Sync trait bounds
3. &mut self plain-class receivers

## Frozen-v2 baseline

reports/baseline.jsonl is the frozen v2 emitter snapshot. 16 fixtures, red:
SELF_REWRAP (SelfRewrap), MUT_SELF (ClosureCapture), MUT_SELF (HandleParamChain).
The other thirteen constructs compile clean under v2's clone-everything
call-site heuristic, so they act as the regression guard while the IR
handle-lowering lands.

The two E0382-attempt fixtures (MultiFieldChain, HandleParamChain) are
engine-level compound reproductions. In isolation they still compile green
under v2's clone-everything heuristic -- E0382 ("value moved here") needs the
full tiqian multi-field expression tree (LayoutResult::new at
line_adjustment_stage.rs:899), not a single-construct reproducer. They stay
as canaries: once the IR handle-lowering lands, these are the first E0382
regression signals.
