# P2a 连通供电、中继与冷却塔

2026-11-08，0.5.29-dev。输入基线为 P0/P1-R 提交 `d684d8e`；本包只接 P2a，不提前切换 P2d 的 600 币/主脑10电/节点新平衡。

> 后续修正：P2a 提交 `1a352a2` 已创建中继/冷却塔定义，但漏把两者加入 `development_128.tres` 的运行时数组。P2b 提交补上该接线并把风能/太阳能一起接入；P2a 的“定义加载”证据以 P2b 复验为准。

## 实现

- `MechGridState` 新增连通覆盖：
  - 以主脑为根 BFS；中继只有**完工 OPERATING 且自身格已被已连通覆盖**时才加入，断开环/未完工/拆除中/基座不供覆盖。
  - 覆盖仍使用“离建筑占地最近格”的圆形半径；中继 1×1、半径6。
  - 覆盖结果只更新 `_coverage`，使用独立 `_coverage_revision` 和变更格集合；不改占用/导航 `_revision`。
- `SimCore`：
  - 结构变化设置 `_coverage_dirty`，`_recompute_economy` 先重算覆盖，再让 economy 读取 `powered`。
  - 覆盖变化只标脏覆盖；生产/单位/普通 HP/维修不触发覆盖重算。
  - snapshot 增加 `coverage_revision`，覆盖视图与 HUD 通过它刷新。
- `MechVisionSystem`：覆盖变化使用 `coverage_changes_since` 更新探索记忆，不每次全图扫描。
- 内容：
  - `content/buildings/relay_node.tres`：B08，1×1，15币/2金属矿，10s，HP150，耗电1，覆盖6。
  - `content/buildings/cooling_tower.tres`：B09，2×2，50币/6金属矿，25s，HP250，耗电1，冷却+12。
  - 两个定义已加入 `development_128.tres`；二级菜单目录已有对应 ID，卡片会随运行时定义开放。
- HUD：
  - 建筑断覆盖显示“断覆盖”；顶部已有电力/冷却余量与赤字。
  - 建筑详情显示冷却预留/供给、中继覆盖扩展。
  - 覆盖视图使用独立 revision 刷新；导航不受覆盖变化影响。

## 检查

| 检查 | 结果 |
|---|---|
| 原生导入 | 无项目 SCRIPT/Parse/Compile 错误 |
| 全部活动 GDScript | 42 个 `--check-only` 通过 |
| 既有视野回归 | 49 checks，0 failures |
| 600 帧启动 | P2a 提交时可玩格/游荡敌正常；中继/冷却塔定义尚未接入运行时数组（P2b 修正） |
| 初始覆盖 | `[coverage] changed_cells=657 revision=2` |
| 临时启动中继探测 | 在主脑覆盖内部放置不会增加覆盖（预期重叠）；未完成断开/冗余/断链的原生验证 |
| 覆盖视图 revision | snapshot 已接 `coverage_revision`，HUD/coverage view 可刷新 |
| 原生建造/断链/冷却 | 未执行；无鼠标键盘操作证据 |

## 边界

- 未验证实际建造中继/冷却塔、串联断开、并联冗余、孤立环、拆除/取消/基座、覆盖恢复、冷却供给与断覆盖停运。语法/启动/覆盖初始计数不替代原生验收。
- 主脑仍为电力60/覆盖12/冷却0；P2d 才切到 600币、主脑10电/覆盖6/冷却4、节点新配方。
- 覆盖变化只更新覆盖相关状态；普通 HP 和维修不会触发。建筑生命/维修不会改变覆盖图。
- 当前覆盖连通算法是主脑根 BFS + 圆形盖格；尚未接风能/太阳能环境电源（P2b）。
