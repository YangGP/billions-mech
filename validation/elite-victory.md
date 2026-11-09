# 精英闭环检查（原型机能力与有限波次胜利）

> 历史技术专题：文中“当前”指记录对应的版本。保留实现来源及当时证据，不继承为0.5.89功能/数值/人工验收。现行规则和待办见[开发计划](../docs/development-plan.md)，最近检查见[0.5.89记录](review-fixes-0.5.89.md)。


本地合入补验（2026-11-07）：已用 Godot 4.7.2 完成导入、语法、既有回归与启动检查；原型机索敌现排除装甲墙，追击 A* 与直达校验也使用墙占用豁免，原先“追击仍绕墙”的边界已修复。以下保留原开发机记录；当时的补验不继承为当前人工验收；现行证据与限制见[验证索引](README.md)，旧bundle审查可从Git提交 `4f8218b` 追溯。

> 2026-11-07 · 0.5.17-dev。范围：原型机电磁庇护与穿墙、对敌伤害收口、有限波次胜利判定与胜利面板。本机 Godot 不可用，以下为静态校验结论；语法/导入/回归/启动与实际操作待引擎可用后补验。

## 接入内容

- **电磁庇护**（waves-enemies.md §8.2 / values.md §11）：`MechEnemyDefinition.shelter_radius`（6.0）/`shelter_reduction`（0.5），prototype.tres 启用；半径内敌方单位（含原型机自身）受到的一切伤害 `maxi(1, ceili(damage × 0.5))`，庇护不叠加（首个命中庇护源生效）；杀死原型机即解除（庇护源存实体引用，同 tick 先死后不再庇护后续命中）。
- **穿墙**（用户 2026-11-07 设定变更：正常速度走过围墙，无翻墙时间）：`MechEnemyDefinition.passes_walls`（prototype 启用）；敌人系统第二行军场 `_proto_field`（剔除 armored_wall 后的建筑列表重建，其余建筑软成本与地形照旧）供穿墙敌种行军，`_blocker_at` 对墙格豁免碰撞；不穿其他建筑（照旧接敌啃开）、不穿障碍地形；A* 追击仍绕墙（已知边界，追击为次要行为）。
- **伤害收口**：`MechUnitSystem.advance` 改返回 `{"enemy_hits": [...]}`（对齐 tower_system 的 "hits as results"）；SimCore `_damage_enemy` 单一结算入口（单位与炮塔火力统一），死亡收尸 `_remove_entity` + 经济/导航重算，无感疫（感疫仅我方资产）。
- **有限波次胜利**：`MechFoundationSettings.total_waves = 4`（0=无限，完整单局规则不变）；`MechWaveDirector._queue_wave` 末尾最后一波放完即 `done`，`exhausted()` = done 且 pending 排空；SimCore `_check_victory`（每 tick 末尾）：波次耗尽且场上无行军敌（marches_to_core，含感疫产物）且无交战敌（order==engaged，含游荡敌拆家）→ `_outcome = "victory"`，时钟暂停、移动挂起（镜像失败路径）；快照 `session.reason` 三态化（"威胁已清除"）。
- **表现**：原型机紫黑大体型独立造型 + 独特血条（foundation_view `_draw_prototype`）；受庇护敌人淡紫弧形描边（快照 `sheltered` 标志，sim 侧计算）；胜负面板按 outcome 区分（map_hud Title/Details/顶栏文案与绿色 WIN 色，main.gd feedback）；小地图原型机大点沿用既有实现。

## 静态校验记录

- 新字段链路：`shelter_radius`/`shelter_reduction`/`passes_walls`（enemy_definition.gd → prototype.tres → enemy_system 判定 → sim_core 庇护/快照）、`total_waves`（foundation_settings.gd → wave_director configure）、`exhausted`（wave_director → sim_core `_check_victory`）、`enemy_hits`（unit_system → sim_core 循环）grep 全链路一致。
- 旧引用清零：enemy_system 无 `building_ids` 残留（全部升级为 `buildings_by_id` 透传）；sim_core 无 `tower_dead`/单位段 `dead` 残留；unit_system 无内部扣血与 `dead` 数组。
- validation/vision_checks.gd L120/L199 引用 `_units.advance` 返回值处忽略返回值，签名改动不破坏现有校验。
- 训练场安全：threat_enabled=false → 波次导演 `_active=false`、phase 恒 silence → `exhausted()` 恒 false，不误判胜利。
- .tres 字段名与 @export 拼写核对一致（prototype.tres：shelter_radius/passes_walls）。

## 设计口径（用户确认）

- 胜利 = 波次敌人清完（无 marches_to_core 存活敌）且无交战中敌人；游荡敌 wandering 不阻止胜利。
- 穿墙 = 原型机以正常移动速度直接走过装甲墙，无翻越时间、无翻越状态（取代早前"6 秒翻越、期间暴露可打"方案，waves-enemies.md §8.2 与 values.md §11 已同步改稿）。

## 待 Godot 可用后补验

1. 语法/导入检查（`godot --headless --path . --import`）与标准开局/训练场无头启动。
2. 既有 49 项视野回归不受 unit_system 返回值改动影响。
3. 实战验收：原型机以正常速度直线穿墙（单排/双排无缝通过、无停顿、不啃墙）；撞非墙建筑照旧攻击开路；不穿障碍地形。
4. 庇护：庇护圈内建造者被塔/卫兵命中减半（塔单发 30→15、卫兵 10→5）；圈外全额；杀死原型机后即时恢复全额。
5. 胜利：W4（或调低波次加速验收）放完并清场后胜利面板弹出（绿标题/威胁已清除/坚守时长）、战场冻结、可查看与重开；游荡敌游荡不阻止、拆家中阻止；感疫产物（builder）阻止；训练场不判胜。
6. 波次预告与 HUD：done 后不再出现新预告；`total_waves=0` 恢复无限波次。
