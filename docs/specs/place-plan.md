# PlacePlan / MutationPlan：写路径的单一契约

状态：草案（Astra 裁定 2026-11-03，待落地）
适用范围：Rust 发射器（`packages/compiler/reflaxe/rust/rustcompiler/`）与 RPlan（`packages/compiler/`）

## 1. 为什么需要它

值读取（read-as-value）的 lowering 被用到了 mutation 路径上：读一个非 Copy 字段会得到一份
owned 拷贝，把这份拷贝当作写入目标，写入就落在一个语句末尾即被丢弃的临时值上。同一天内
这一族缺陷在三个不同入口复发：

| # | 入口 | 错误形态 |
|---|---|---|
| 1 | `Bytes.set` | `(self.block).clone()[i] = v`：Sha256 每个输入字节写丢，空输入仍正确，只在 3 条指纹 golden 上暴露 |
| 2 | 容器可变方法（`Map.set/remove/clear`、`Array.remove/insert/splice`） | `(self.map).clone().insert(...)` |
| 3 | 嵌套下标写 | `((arr[i]).clone())[j][k] = v` |

每次修法都是「在调用点调用 `mutableReceiver` 或设置一个 `renderingInPlaceMutatorReceiver`
开关」。现在有 4 个动态开关、9 个调用点，正确性依赖「投影深度」和「剥掉外层 clone」。

判据（写目标的接收者必须是 place）本身是正确的；错在它是**逐点字符串修补**，没有成为
可验证的契约。

## 2. 强不变量

> 所有 source mutation 必须保持其源程序指定的写入位置或被修改对象身份。

不简化为「生成文本里不得 clone」，也不简化为「接收者必须是 Rust 左值」：这两种判据会误伤
合法的句柄克隆（`Rc::clone` 保持 referent 身份）与合法的临时对象方法调用
（`new C().mutate()`）。

## 3. 契约的三个轴（不得混为一谈）

- **storage representation**：这块存储怎么表示（现有 `RepresentationPlan.role`：
  `ClassHandle` / `TraitHandle` / …）
- **receiver ABI**：接收者怎么传（`&self` / `&mut self` / by value）
- **place / access intent**：本次访问是值读还是写入，写到哪块存储

`PlacePlan` 与 `RepresentationPlan` **正交**，不新增与 `ClassHandle` 互斥的 role。

### 3.1 最小字段

```
AccessIntent    = ReadValue | AssignSlot | MutateReferent        (必要时 ReadModifyWrite)
MutationTarget  = StorageLocation(root + projections) | ObjectIdentity(identityOrigin)
PlacePlan       = root
                + projection 链
                + 最终 repr
                + 读写权限
                + 求值顺序/次数
                + alias / storage relationship
                + borrow scope
                + 必要的 writeback 与退出行为
```

句柄槽位与它指向的对象**不能合成同一个目标**。

projection 每一步标注：

- `PreserveLocation`：保持位置（字段槽、数组元素位置）
- `PreserveReferentIdentity`：保持被指向对象身份（`Rc::clone`、`borrow()`）
- `DetachedValueWithWriteback`：脱离的值，必须携带完整 writeback 证据

不支持或证据缺失 → 诊断失败，不生成。

### 3.2 核心判据

对每次 mutation，plan 必须证明：

1. 目标与源语义要求一致；
2. 所有中间投影保持该关系，或具有完整 writeback；
3. root / index / RHS 的求值次数与顺序、可观察副作用、异常路径保持源语义。

写回时机不是无条件「函数最后」，必须满足源语义；无法证明时不生成。

## 4. clone 的裁决（由 repr + operation 语义声明，不看名字）

| 情形 | 判定 |
|---|---|
| `Rc::clone` 等句柄拷贝 | `PreserveReferentIdentity`，**允许**：副本指向同一对象，改 referent 正确 |
| `Vec` / `Bytes` backing value 的整体 clone | `DetachedCopy`：要改原容器且无合法 writeback → **拒绝** |
| 可空句柄（`Option<Rc<RefCell<T>>>`） | 先处理 presence，再取保持身份的句柄并借用；允许克隆句柄 |
| 可空值/容器（`Option<Vec<T>>`） | 复制 payload 后修改不会自动写回 Option 槽：必须保留原 place 或显式 writeback |
| `h.field = replacement` | 更新字段槽：克隆旧句柄**无法**完成替换 |
| `h.field.mutate()` | 允许克隆句柄后改同一 referent |
| `new C().mutate()` | 合法：源语义的目标本就是该临时对象，不得因「必须已有局部左值」拒绝 |

## 5. 三个入口统一请求计划

```
赋值        assignTarget        (AssignTargetPlan.hx)
索引写      optionContainerIndexAccess(..., mutable) / mutableArrayReceiver
可变方法    in-place mutator 调用点（Map/Array/Bytes 等）
```

三者共用**同一个递归 place/receiver planner**，而不是三处各做一遍判定。值读取另走
`prepareValue`。planner 必须沿 field / index / nullable projection **递归传递目标意图**，
不能先渲染成值再剥外层 clone。

可变方法的修改目标由**已解析的 effect 语义** 决定（改 receiver、改容器、改元素、还是
改别处），不能只按 `set`/`remove` 这类名字判断。

## 6. 迁移路径

1. 引入 `PlacePlan` / `MutationPlan` 类型与递归 planner（新代码优先）。
2. 三个入口改为请求 planner；现有逐点修复保留为回归对照。
3. 迁移完成后删除 `renderingInPlaceMutatorReceiver`、`renderingAssignTargetReceiver`、
   `renderingMethodReceiver`、`mutableReceiver` 的字符串剥离逻辑。

## 7. 验收

### 7.1 硬性门

- 所有 mutation 构造节点带**已验证** `MutationPlan`；
- 缺计划，或 `DetachedCopy` 无 writeback，在打印/提交产物**之前**失败；
- 不接受「事后 trace 声称有计划」「语法上没有 clone」「只有空输入通过」「validator 只检查开关已设置」。

### 7.2 矩阵

至少覆盖：

- field / index / nullable 混合投影
- 深度 1 / 2 / 3 及更深组合
- `AssignSlot` 与 `MutateReferent` 两类意图
- 值容器与 handle 容器
- alias 观察（旧别名应看到的变化必须看到）
- 带副作用的 index 与 RHS（求值次数与顺序）

### 7.3 判别变异（必须被抓住）

1. 把 `PreserveReferentIdentity` 偷换成 `DetachedCopy` → 必须失败；
2. 把合法 handle clone 一概禁掉 → 必须被正例抓住。

### 7.4 最终

运行相关 Rust 实际构建与行为/golden。三个 gate 目标（engine-rust-f32、engine-rust-f64、
protocol-rust）读数不得回退。

## 8. 何时必须升级而不是逐点修

出现以下任一条件：

- (a) 两个以上入口独立判断同一写入位置/别名规则，且无共同计划作为权威；
- (b) 正确性依赖投影深度、全局渲染开关或「剥掉外层 clone」；
- (c) lowered 只剩文本，无法回答 target identity/location 是否保持；
- (d) 新增一个 field/index/nullable 组合要再登记名字或补调用点；
- (e) validator 无法在生成前拒绝 detached mutation，只能靠运行结果碰运气。

允许局部修复必须**同时**满足：已有统一可组合且实际被执行的契约；错误仅是该入口漏调用或
某个 projection 实现违反已明确契约；修复使用既有 planner、不新增语义判断/开关；兄弟入口
覆盖清单完整；一个有针对性 negative control 能证明遗漏会被抓到。

新 projection 的局部实现可以修，但必须加入统一计划类型与验证，不能成为旁路。

## 9. Policy 层声明面（Astra 裁定，2026-11-03）

定性：**缺 Policy**，不是 PlacePlan 判据错。`isPlace=true` / `verified=true` 硬编码
是未经权威事实证明的判定，令 fail-closed 永不触发。

### 9.1 分工

- **SemanticPolicy** 声明 representation / operation 的**基础能力**：alias、storage、
  mutability。声明域是权威事实，不是 planner 反推的结果。
- **RPlan / PlacePlanner** 只依据这些声明、静态/实例根事实与投影链**推导本次路径**的
  place 与 identity，**不得创造未声明能力**。

### 9.2 最小声明面

```
storageKind          = Value | SharedReferent | StaticSlot | BorrowedView | Unknown
cloneRelation        = DetachedCopy | PreserveReferentIdentity | NoClone | Unknown
mutationCapability   = Immutable | MutatesReferent | MutatesSlot | RequiresWriteback | Unknown
placeCapability      = Place | NonPlace | Conditional | Unknown
nullableProjection   = PreservePresence | UnwrapBorrow | WritebackRequired | NonPlace | Unknown
staticStorage        = MutablePlace | Immutable | RuntimeGuardedPlace | ReadOnlyView | Unknown
operationContractId  = 引用具体 set/remove/index/write 的 alias/writeback 契约
```

representation 表必须覆盖**所有可进入 mutation 的类型与操作**。

### 9.3 缺声明 → fail closed

对任何会产生写入、可变调用或需要 place/identity 证明的路径：`Context.error` + 拒绝生成。

**禁止**保守默认成 `isPlace=true`、`PreserveReferentIdentity` 或隐式 writeback。

只有纯只读 value lowering 可在显式 `Unknown` 下继续，且其结果**不得被复用为 mutation
operand**。缺事实是未知，不等于不可变或可写。

### 9.4 静态存储（FStatic）

根 place 性**由 Policy 声明**，planner 负责组合验证：

- `staticStorage = Immutable | ReadOnlyView` → 静态下标写在 planner 中必然报错；
- `MutablePlace | RuntimeGuardedPlace` → 还必须有对应的运行时访问/writeback 语义才可生成。

**不得**由 RustExpr 依 `final`、名字或生成文本猜测。

负向控制必须直接命中 policy/planner：`static final ARR[0] = 9` 在**生成前**失败；并且
把 policy 错改为 `MutablePlace` 时判定确实改变：**不是只检查最终 Rust 文本**。

