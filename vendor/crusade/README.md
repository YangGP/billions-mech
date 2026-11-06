# vendor/crusade — 分离数学（M5 机潮行军）

来自 [Crusade RTS](https://github.com/saman-mb/crusade-rts)（MIT © 2026 saman-mb，全文见本目录 LICENSE）。
锁版本：HEAD `e4929c8`（2026-07-26）。选型依据与候选对照见 [复用调研 §9/§10](../../docs/reuse-research.md)。

## 采用文件（逐字未改）

- `steering.gd` — 纯静态分离（逆距离权重、NaN/重合防护）与期望速度合成。配合 sim 网格桶邻居表满足"分离使用空间分区"；分离半径由调用方注入：行军/攻击单位 0.6，攻击建筑 0.3（允许部分重叠），口径见 [M5 记录](../../validation/m5-threat-defense.md)。

## 已移除与不导入的部分

- `flow_field.gd`（均匀成本 BFS 流场）：曾用于 M5 切片一行军；按用户决策改用加权软成本场（`sim/march_field.gd`，建筑格 1 + min(HP,400)/8，Mindustry Pathfinder 口径）后无法表达"缺口足够便宜时弃墙走缺口"，已从 vendor 移除。上游源码仍在本地参考副本 `d:\fish\crusade-rts\`，未来若游荡敌噪声场需要共享场，按 §2 流程重新评估。
- `flow_follower.gd`（行军积分器）：耦合 Crusade 的等距/高程几何（EntityPlacement/IsoCoord），且墙卫语义为"贴墙滑动"——与本项目"撞墙打墙"（建筑阻挡切攻击）规则冲突；其"步进逐级降级、绝不站进实体格"守卫思路在 sim 敌方行军集成中吸收。
- 其余 A*/阵型/编辑器模块：本项目已有对应实现。
