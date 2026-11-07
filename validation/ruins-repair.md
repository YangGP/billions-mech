# 基座与维修规则实施与检查

本地合入补验（2026-11-07）：已用 Godot 4.7.2 完成导入、语法、既有回归与启动检查；补齐通行表声明、一键修复信号/快照/连接、重建错误提示，修复清除中基座显示和伤害守卫。交战扫描现按模拟频率折算 0.5 秒。以下保留原开发机记录；最新证据与操作验收限制见 [M6 bundle 审查](m6-bundle-review.md)。

更新：2026-11-07，0.5.16-dev。规则已接入并完成两轮修正（0.5.15 基座边界、0.5.16 交战状态判定）；本机 Godot 不可用，全部原生检查未执行，实战手感未验收。

## 接入内容

- **交战状态维修暂停**（`sim/building_state.gd` + `sim/economy_system.gd` + `sim/sim_core.gd`）：建筑被攻击即进入交战状态（`threatened`，`damage_building` 命中即时置位）；周边 `THREAT_RADIUS`（6 格）内存在敌方单位期间维修暂停——不回血、不扣币、不积累余数。`_scan_combat_threat` 每 0.5 秒（`COMBAT_SCAN_TICKS`）扫描：交战中的建筑周边（footprint 矩形距离 6 格内）无敌方单位即脱离交战，维修自动恢复；脱离后敌军路过但不攻击不再封锁，再次被攻击重新进入。判定用 sim 权威位置（迷雾中的敌军同样维持交战）；训练靶（非敌军实体）不触发。面板状态显示"交战中"/"交战中 · 维修暂停"；维修开关可提前打开，脱离交战后生效。取代 0.5.14 的"最后受击后 5 秒"时间窗。
- **被毁分流**（`sim/sim_core.gd` `damage_building`）：hp 归零时——主脑走失败结算（`_remove_building`，无基座）；**施工中（CONSTRUCTING）被毁不留基座**，直接 `_remove_building` 彻底移除（不退款、释放占用与矿点绑定，原址可立即另建）；完工/拆除中（OPERATING/DEMOLISHING）被毁转 `Phase.RUINED`（`mark_ruined` 清进度/维修/交战/战斗/账目字段，`paid_cost` 归零）。感疫在被毁瞬间照常触发（占容资产，含施工中）；被毁工厂订单不退款清除（`remove_factory(id, false)`）。
- **基座无碰撞不阻挡**（`sim/grid_state.gd`）：通行豁免集合 `_pass_through`——`set_pass_through(entity_id, enabled)` bump revision；`is_walkable`/`mobile_position_clear` 放行豁免占用，放置校验（`preview_footprint`/`inspect_cell`）继续用 `occupant_at`（保留"基座上不可另建"与矿点绑定）。A*（`grid_navigation`，按 revision 重建）、RVO 障碍（`crowd_navigation._sync_obstacles`，按 revision + is_walkable）、单位/敌人移动校验、出厂/集结/阵型/出生带全部经 `is_walkable` 单点自动跟随；`enemy_system._blocker_at`（直查 occupancy 的圆形身体阻挡）补 `grid.is_pass_through` 放行。`_ruin_building` 置豁免；REBUILD 执行清除豁免（恢复"下单即阻挡"）；`release`/`configure` 清理防残留。
- **行军场**（`sim/march_field.gd`）：基座格按纯地形成本（hp<=0 不进 soft 表）——机潮从墙毁缺口直涌穿过基座，不绕行不卡死（0.5.14 的基座格 INF 已撤销）。
- **重建（折扣施工式）**：命令 `REBUILD`——仅 RUINED、仅校验资金（预留沿用基座原占用）；付全额 50%（`rebuild_cost()` 逐资源向下取整）、按施工时长推进、血量随进度爬升、完工恢复运行；`paid_cost`=实付重建价；工厂重新注册（队列/集结点重置默认）；`note_construction` 噪声照旧。
- **清除基座**：`DEMOLISH` 放宽至 RUINED——先 `paid_cost=ZERO`（拆除完成退款自然为 0），复用拆除时长；`CANCEL_DEMOLISH` 恢复目标 `RUINED if hp<=0 else OPERATING`；`_wall_connections` 不连接基座邻居。
- **一键修复**：命令 `REPAIR_ALL` + 快照字段 `repair_all`（`_repair_all_status`：本局结束/有建筑交战中（周边 6 格内有敌军）/没有受损的完工建筑三类拒绝原因 + count）——门槛为**全部建筑脱离交战状态**；对所有 OPERATING 且 hp<max 建筑 `repairing=true`；基座重建不在范围。HUD 工具栏"一键修复"按钮灰显附原因。
- **联动**：视野/敌索敌/炮塔/生产/收入沿用既有 `hp>0`/`operating()` 守卫，基座天然无视野、不被索敌、不开火、不产出。表现层：基座画扁平深色底座+红叉（`foundation_view._draw_ruin`）、拾取热区高度 10、小地图基座半透明、HUD 面板重建/清除分支与确认框文案（含"不阻挡通行"说明）。

## 检查证据

本机（Windows）无 Godot 可执行文件（前批已确认），按 AGENT.md 仅静态逻辑校验：

| 检查 | 结果 |
|---|---|
| 旧窗口残留 | Grep `last_damage_tick`/`repair_suspended`/`REPAIR_SUSPEND_SECONDS` 于 sim/presentation 全部为空；`THREAT_RADIUS`/`COMBAT_SCAN_TICKS`/`_scan_combat_threat`/`threatened` 常量、函数与字段逐一定位确认 |
| 交战链路 | `damage_building` 命中置位 → `advance_repairs` 跳过（位于 `repair_remainder += 1` 之前，不积累）→ `_scan_combat_threat` 脱战清除（仅扫 threatened 且 hp>0 的建筑，敌方实体判定含 `enemy_definition != null`，矩形距离平方比较） |
| Phase 站点审查 | Grep `Phase\.` 全库：economy/construction/tower/vision/map_hud/foundation_view/minimap 均正确处理 RUINED；无 else 兜底遗漏 |
| hp 守卫一致性 | enemy_system/march_field/vision 的 `hp<=0/hp>0` 过滤一致；march_field 已撤销 INF |
| 通行豁免链路 | `is_walkable` 为通行判断唯一收口；`_blocker_at` 已补 `is_pass_through`；`_ruin_building` 豁免赋值、REBUILD 清除、`release`/`configure` 清理全覆盖（**0.5.16 附注：0.5.15 提交中 `_ruin_building` 的豁免赋值行因编辑未持久化而缺失，提交版基座实际仍阻挡；本轮已补齐并验证落盘**） |
| damage 分流 | 主脑/施工中（移除）/其余（基座）三分支 + 感疫前置 + 分流后统一 `_sync_navigation()` 核对 |
| 签名/命令/快照键 | `advance_repairs(buildings, hz)` 调用方同步；validate/execute/_on_command_finished 三处 match 含 REBUILD/REPAIR_ALL；`threatened`/`rebuild_cost`/`repair_all` 键生产者消费者一致 |
| 负血量防回归 | `mark_ruined` 与 REBUILD 执行均置 hp=1/built_hp=1/elapsed_build_ticks=0 |

**编辑持久化事故记录（0.5.16 轮）**：本轮实施中发现多次 Edit 工具"成功"回执未实际写入磁盘（building_state 常量替换、sim_core 常量/扫描函数/`_ruin_building` 豁免行、building-economy 条目均出现过一次未落盘），其中 `_ruin_building` 豁免行缺失已随 0.5.15 提交入库（提交版"基座不阻挡"未生效）。本轮全部补齐并对每处编辑执行 grep 落盘验证；后续批次应保持"编辑后即验证"流程。

**未执行（待有 Godot 后补验）**：`--import`、逐脚本 `--check-only`、`validation/vision_checks.gd` 回归、标准/训练场启动、渲染画面。

## 验收边界

- 施工中被毁：无基座、原址立即可建；完工/拆除中被毁：基座保留占位与矿点绑定，单位与机潮可穿过，重建下单起恢复阻挡。
- 交战状态：被攻击进入，周边 6 格内无敌军即脱离（扫描间隔 0.5 秒，命中即时置位）；迷雾中的敌军同样维持交战（面板显示"交战中"但可能看不见敌军，属预期信息反馈）。
- 工厂重建后生产队列与集结点重置为默认；重建后再拆除退款=实付 50%×50%。
- 一键修复门槛含施工/拆除中受击的存活建筑（threatened 不分相位）。
- 基座格 `inspect_cell` 显示"可通行 + 建筑占用"并存——占位≠阻挡，语义正确。
- 人工待验：被攻击后交战状态与面板显示；杀光周边敌军后维修自动恢复且不补扣币；敌军路过不攻击不再封锁、再次被攻击重新进入；一键修复灰显/启用切换与 count；施工中墙被打到 0 后原址可立即另建；完工墙被毁后单位/敌人可穿过基座、机潮从缺口直涌；REBUILD 后基座格恢复阻挡；清除基座无退款释放绑定；被毁工厂订单不退款；主脑失败结算不变。
