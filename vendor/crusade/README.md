# vendor/crusade — 流场与分离（M5 机潮行军）

来自 [Crusade RTS](https://github.com/saman-mb/crusade-rts)（MIT © 2026 saman-mb，全文见本目录 LICENSE）。
锁版本：HEAD `e4929c8`（2026-07-26）。选型依据与候选对照见 [复用调研 §9](../../docs/reuse-research.md)。

## 采用文件（逐字未改）

- `flow_field.gd` — 均匀成本 4 连通 BFS 积分场（PackedInt32Array 扁平缓冲，`recompute(goal)` 复用缓冲）+ 8 邻最低成本流向向量。可通过性经构造器 `walkable: Callable` 注入。本项目注入"地形层可通过、不含建筑"，满足"只计地形，玩家建筑由实际碰撞/攻击处理"与无头 sim 红线。
- `steering.gd` — 纯静态分离（逆距离、NaN 防护）与期望速度合成数学。配合 sim 网格桶邻居表即满足"分离使用空间分区"。

两文件在源仓库带 headless 单测（`src/core/tests/test_flow_field.gd`、`test_steering.gd`）与 CI；仅依赖 Godot 核心类型（Rect2i/Vector2i/PackedInt32Array/Callable），无 Node/场景/TileMap 依赖，4.4 与 4.7 间无 API 差异。

## 刻意不导入的部分

- `flow_follower.gd`（行军积分器）：耦合 Crusade 的等距/高程几何（EntityPlacement/IsoCoord），且墙卫语义是"贴墙滑动"——与本项目"撞墙打墙"（建筑阻挡切攻击）规则冲突。其"步进逐级降级、绝不站进实体格"的守卫思路在 sim 敌方行军集成中吸收。
- 其余 A*/阵型/编辑器模块：本项目已有对应实现。

## 集成口径与已知限制

- 主脑固定 + 地形静态 ⇒ 波次流场整局只算一次，符合"不因建墙/墙塌重算"。
- 均匀成本 BFS：崎岖地不比开阔地贵，敌人不因崎岖绕路、仅移动层减速——与 map-terrain.md §3"主口前天然迟滞"意图一致；若试玩要求按权重择路，扩展即替换核心算法，按 AGENT.md 属重新自研，须另行记录。
- `flow_at` 的对角流向无防切角守卫（源仓库由 follower 墙卫兜底）：敌方行军集成在步进校验中处理，与玩家 A* 的 DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES 语义对齐。
- 游荡敌不共用主脑流场：数量小，直接走既有 AStarGrid2D 逐敌寻路。
