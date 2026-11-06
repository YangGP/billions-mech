# vendor/crusade — 分离数学与流场（M5 机潮行军）

来自 [Crusade RTS](https://github.com/saman-mb/crusade-rts)（MIT © 2026 saman-mb，全文见本目录 LICENSE）。
锁版本：HEAD `e4929c8`（2026-07-26）。选型依据与候选对照见 [复用调研 §9/§10](../../docs/reuse-research.md)。

## 采用文件（逐字未改）

- `steering.gd` — 纯静态分离（逆距离权重、NaN/重合防护）与期望速度合成。**在用**：配合 sim 网格桶邻居表满足"分离使用空间分区"；行军/攻击单位用 0.6 半径，攻击建筑用 0.3 半径允许部分重叠（口径见 [M5 记录](../../validation/m5-threat-defense.md)）。
- `flow_field.gd` — 均匀成本 4 连通 BFS 积分场 + 8 邻流向。**保留未接线**：曾用于 M5 切片一行军，随后按用户决策改用加权软成本场（`sim/march_field.gd`，建筑格 1 + min(HP,400)/8，Mindustry Pathfinder 口径）——均匀成本无法表达"缺口足够便宜时弃墙走缺口"。保留作纯逻辑参考与未来噪声目标场候选（游荡敌聚拢若需要共享场时按 §9 流程重新评估）。

## 刻意不导入的部分

- `flow_follower.gd`（行军积分器）：耦合 Crusade 的等距/高程几何（EntityPlacement/IsoCoord），且墙卫语义为"贴墙滑动"——与本项目"撞墙打墙"（建筑阻挡切攻击）规则冲突；其"步进逐级降级、绝不站进实体格"守卫思路在 sim 敌方行军集成中吸收。
- 其余 A*/阵型/编辑器模块：本项目已有对应实现。
