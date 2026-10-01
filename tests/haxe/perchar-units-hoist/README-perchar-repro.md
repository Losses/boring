# 逐字符 `units` 二次缺陷：可复现探针

这条探针把**生成码原样**（Tiqian `org/tiqian/test/trace/test_trace_render.rs` 的
`test_trace_render_expand_scientific` + `test_trace_render_scientific_match`，
从 `fix/rust-perchar-units-for-loop` 前后的两棵生成树里逐字节取出）装进一个自足
crate，只把 `crate::runtime::*` 换成同名同语义的最小实现，用来量这条路径的时间与
`units()` 调用次数。它不依赖任何下游检出，因此可以在这里直接跑。

## 三个变体（同一份主体，只差 hoist 落点）

| 文件 | 含义 |
|---|---|
| `perchar-cost-repro.rs` | **修复后形状**：`units`/`unit_count` 提到函数入口一次，内层函数复用调用方传入的 `&[u16]` |
| `perchar-cost-control.rs` | **修复前形状**：内层函数在每次进入时重新 `u_string::units(&s)` 一份自己的副本（修复删掉的那个死 hoist） |
| `perchar-cost-unitsfree.rs` | **归因对照**：循环体与调用次数都不变，只把 `units()` 换成 O(1) 替身 |

## 跑法

```sh
RUSTC=$(command -v rustc)          # 1.98.0
for v in repro control unitsfree; do
  $RUSTC -O --edition 2021 --crate-type bin -o /tmp/perchar-$v perchar-cost-$v.rs
  for n in 100000 200000 400000; do /tmp/perchar-$v $n; done
done
```

## 实测（release，-O）

```
repro     bytes=100002 walk_units_calls=33335  walk_ms=4934
repro     bytes=200001 walk_units_calls=66668  walk_ms=19165
repro     bytes=400002 walk_units_calls=133335 walk_ms=88794
control   bytes=100002 walk_units_calls=66669  walk_ms=17422
control   bytes=200001 walk_units_calls=133335 walk_ms=53648
control   bytes=400002 walk_units_calls=266669 walk_ms=232117
unitsfree bytes=100002 walk_units_calls=0      walk_ms=0
unitsfree bytes=200001 walk_units_calls=0      walk_ms=2
unitsfree bytes=400002 walk_units_calls=0      walk_ms=3
```

读法：`walk_units_calls` 与输入成正比（≈ n/3，每个字符一次），时间每翻倍输入就 ×4
（4.9→19.2→88.8 秒），即 **O(n²) 的 `units()` 分配/拷贝**；把 `units()` 换成 O(1)
后同一条循环降到 0/2/3 毫秒（线性），说明开销**全部**来自这个 hoist，不是循环本身。
`control` 的调用数正好是 `repro` 的两倍：修复前内层函数每次进入都多 hoist 一份。

生成树层面的同向读数：`org/tiqian/test/trace/test_trace_render.rs` 里
`u_string::units(` 出现次数 **13 → 7**，整树 `diff -rq` **22 个文件不同**。
