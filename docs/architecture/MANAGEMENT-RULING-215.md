# Management ruling, round 215

Retained verbatim because it is binding. Operative points:

- **Contract 3 is now ACHIEVED.** The CI gate extracts warning lines naming the
  generated trees, writes count + matching lines + domain + baseline
  reconciliation into the job summary on every run including red ones, and fails
  on a missing log, an unparseable count, or a count deviating from the recorded
  baseline. The baseline 0 is supported by a source revision and a full-suite log
  path - it is not assumed. No `continue-on-error` and no threshold-raising path.
- **The `out/` guard remains "present, never triggered - not an exercised guard"**
  and does not change that verdict.
- **The `package-artifacts.test.ts` tracked-file damage is NOT in the pause's
  scope but IS a blocking integrity repair**: implementation expansion is paused,
  yet before the test is restored or any verification that triggers it is run, the
  `try/finally` root cause must be fixed with a discriminating proof. **A manual
  `git checkout` restore must not be counted as the fix or as proof.**
- **No second P08 review may be dispatched yet.** Wait for `p08-review-1` to be
  delivered and its conclusion recorded; then dispatch the second to a seat
  distinct from the first and not involved in the P08 implementation or the
  `c8ae0054` freeze.
- **Next single action**: wait for `p08-review-1`; suspend the second review and
  all non-CI-gate work until then.

# SOL-REVIEW-215

## 裁定

### ① 契约 3 与 CI warning 计数闸门

**裁定：契约 3 现已达成。**

按本轮交付的实现和判别性验证，该闸门满足第 195 轮裁定的全部关键要求：

- 从命名的 `reference/*/gen` 与 `reference/*/gen-tests` 生成树提取 warning 行；
- 将 warning 计数、匹配行、收集域和基线对账写入 `$GITHUB_STEP_SUMMARY`；
- 报告步骤使用 `if: always()`，红跑也保留可审计结果；
- 日志缺失、计数不可解析、计数少于或多于记录基线均失败；
- 当前实测基线为 `EXPECTED_GENERATED_TREE_WARNINGS=0`，且该数值有源修订和完整套件日志路径支撑，不是假定值；
- 已有判别性证明：green 为 `count 0 / exit 0`，缺失日志为 `exit 1`，注入 warning 为 `count 1`、`::error::`、`exit 1`；
- workflow 没有 `continue-on-error`，也没有提高阈值的路径。

因此，这不是仅报告 warning 的装饰性输出，而是缺失、偏少、偏多均失败的可验证 CI 闸门。`out/` 守卫仍只能记为 **present, never triggered — not an exercised guard**，不改变契约 3 的判定。

域漂移已如实记录为 `304/55`，其基线 pass/fail 数字仍明确绑定 `303` 文件域；这项记录不冒充新的域基线清偿。

### ② `package-artifacts.test.ts` 的反复损害是否属于“其余事项暂停”范围

**结论：根因修复不属于第 195 轮“先落地并验证 CI warning 计数闸门”的交付范围，因此不能以该指令为理由继续扩大本轮实现。**

但它也不是可以忽略的普通旁支：当前还原语句不在 `try/finally` 中，失败路径会改写受跟踪的 `samples/boring/MathNaNTestSupport.hx`（`Test.equals 5` 被改成 `0`），并且已重复发生至少三次。这是测试完整性和证据可信度缺陷。后续恢复该测试或开展会触发它的验证前，必须修复并交付判别性证明：故意走失败路径后，该受跟踪文件内容仍与进入测试前一致。

在本轮裁定中，该事项的状态为：**暂停实现扩展，但保留为恢复验证前的阻断性完整性修复；不得把人工 `git checkout` 还原当作根因修复或证明。**

### ③ P08 第二份独立复核

**现在不得派。**

`p08-review-1` 尚未交付，尚无第一份复核的已记录结论。因此继续遵守第 195 轮顺序约束：先接收并记录第一份独立复核；随后才把第二份复核派给不同于第一席、且不参与 P08 实现和 `c8ae0054` 冻结工作的独立席。第二复核只覆盖冻结对象、边界行为、证据链和台账一致性，不重新扩大实现范围。

### ④ 下一轮最小动作

**唯一指令：先等待 `p08-review-1` 交付并记录结论；在此之前暂停第二份复核派席和所有非 CI 闸门事项，第一份交付后立即派给不同独立席进行第二份 P08 复核。**

## 当前状态

- HEAD：`99ba67fd`
- 台账 PASS 行：`2`
- 契约 3：**达成**
- `out/` 守卫：**存在，未触发，未验证**
- P08 第一复核：**已派，未交付**
- P08 第二复核：**未派，当前禁止提前派出**
- 本文件之外不修改仓库或任何既有文件。
