# 架构治理：问题分类、契约与分层验证

本目录是 Boring 架构治理三项产物的落地位置：

| 文件 | 内容 |
|---|---|
| `PROBLEM-CLASSIFICATION.md` | 跨目标共用的**问题分类**（A–F 六类编译器职责及其属主） |
| `ARCHITECTURAL-CONTRACTS.md` | **架构契约**（接口两端各自承诺什么） |
| `LAYERED-VERIFICATION.md` | **分层验证方案**（每层用什么可观察量检验，以及该判据何时骗人） |

## 与既有文档的关系

- **约束性验收标准**是 `docs/specs/style/02-translator-implementation-standard.md`
  （计划 `:63` 把 "acceptance rules" 指派给它）。本目录不重复该标准，
  只在契约 3 引用它并推出其**收集**含义（没有套件在跑 ⇒ 不产生计数 ⇒ 标准被绕过）。
- **任务顺序与状态**是 `docs/architecture-work-plan.md`（计划 `:65` 自述其职责为
  "task order, assignments, dependencies, and programme status"）。本目录不取代它。
- **边界策略记录**是 `dc-warn/out/boundary-policy-record/RECORD.md`；本目录引用其
  CORRECTION 13 的结论（三条 REFUSED 行为 PLANNER-CELL ONLY），不复制其正文。

## 这三份文档的来源

取自本程序既有的调查记录、两席架构咨询（SOL2 / Astra）与 CODEX-AUDIT，
以及本会话四处已修复缺陷的机制。**不是新调查**；目的是把散落在报告与
会话中的设计结论汇成可引用的形式。

## 每份文档都带"未决"一节

未决项是文档的一部分，不是缺陷：构建期诊断是否计入验收、J 类迁移的契约、
命名一致性的归类、单返回快速路径的缺口，均在各自文档中具名。

## Worktree isolation (added after a real incident)

**Work in your own worktree. Never `git checkout` in the shared coordination
worktree.**

On 2026-09-30 a dispatched seat, following its brief literally, ran a branch
checkout inside `/home/losses/Development/tq-workspace/boring-wt-architecture`.
That single act moved **every** other running seat's baseline: the shared tree went
from the line under test to an unrelated branch at an older commit, and any seat
that read tree state, generated artifacts, or ran a suite in that window was
measuring the wrong thing. Nothing was lost - the commits were reachable from
`--all` throughout - but three seats had to be told their readings might be
invalid.

The cause was not the seat. Its brief said "claim this branch" and it did. **The
brief was wrong**: this repository already keeps its parallel work in dedicated
worktrees (dozens of them under `dc-warn/worktrees/` and beside it), and the
instruction failed to say so.

**The rule, therefore:**

- To work on a branch, create your own tree: `git worktree add <path> <branch>`.
- The shared coordination tree is for **reading only** - `git log`, `git show`,
  `git ls-tree`, `git status`. It may not be checked out, reset, or committed to.
- If a task is genuinely a one-tree operation, say so and work in an export
  (`git archive`) instead, which is what the gate tooling already does.
- A dispatch brief that names a branch **must** say where the work happens. A brief
  that omits it is defective, regardless of how the seat behaves.

This is recorded here rather than left in chat because it is a property of how this
repository is worked, not a one-off mishap.

## Sign-off checklist (this session's lessons, collected)

Before accepting a delivery, run these in order. Each step corresponds to a trap this
session actually hit; none of them is hypothetical.

1. **Which tree does it hold on?** `git rev-parse --verify <branch>` (does it exist) ->
   `git merge-base --is-ancestor <commit> arch/agent-guided-governance` (is it in base) ->
   **open the file in the shared tree** (what shape is base actually in). The third step is
   not optional: a hardened guard was reviewed and signed off yet was never an ancestor of
   base, so base ran the weak copy and the same input reached OPPOSITE verdicts on the two.
2. **Does the load-bearing artifact have a commit?** Tools, guards, fixtures, drivers and
   assertion scripts must pass `git ls-files --error-unmatch` and come out of
   `git archive HEAD`; evidence may live in reports. Measured here: 37 of 37 worktrees were
   detached HEAD and all 37 had uncommitted changes.
3. **Can the criterion fail?** "The correct case passes" is not verification. Produce a
   deliberately wrong input and watch it FAIL: a gate needs BOTH the loose and the strict
   rc (equal rc means the gate does not exist); a fixture needs a mutant or reverse
   control; "changed the emitter" needs a regenerate-and-diff (one 38-line change produced
   0 differing files across the whole generated tree).
4. **Are the rc and the count measured correctly?** Read rc directly, never through a pipe;
   count diagnostics by SHAPE (`^error(\[E[0-9]+\])?:`, or
   `^[^ ]+\.swift:[0-9]+:[0-9]+: (warning|error):`), never by substring - caret/context
   lines and rustc's `--explain` hint both double-count.
5. **Does the manifest verify from one command at the repo root?** If it names
   git-ignored paths then "rc=0" holds only on the author's working copy. Label reachable
   and unreachable entries as separate sections, and verify in a clean `git archive` export.
6. **After merging, check where it landed.** `git rev-parse --abbrev-ref HEAD` plus step 1's
   is-ancestor: one round merged four times onto a working line while the declared base
   never moved, so newly created worktrees could not see the fixes.
7. **How wide is the claim?** If a report says "passed" where it did not measure, downgrade
   to `partly-confirmed` with the condition; `not-reached` needs its search evidence (which
   paths were tried), otherwise "the environment lacks it" is indistinguishable from "nobody
   looked" - one `haxelib` sat in the very store directory as `haxe`.
