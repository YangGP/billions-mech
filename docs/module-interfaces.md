# 模块接口参考

对应 0.5.89-dev（Godot 4.7.2 / GDScript），更新于 2026-11-10。本文是运行目录现有公开接口的静态整理，不是新增 API 规划；实现与数值分别以源码和 `content/*.tres` 为准。系统规则见[代码架构](architecture.md)，完成度见[开发计划](development-plan.md)。

## 阅读约定

- GDScript 没有访问修饰符；本文把**不以 `_` 开头的顶层声明**视为公开接口，`_` 前缀一律视为内部实现。
- 跨层数据只有三种形态：**命令 payload**（输入意图）、**值快照 Dictionary**（模拟 → 表现）、**生成请求/命中结果 Dictionary**（子系统 → SimCore）。
- 模块不通过场景树互相查找；表现层只调用 `present_*` 系列方法，绝不写模拟状态。

## 1. 分层与数据流

```text
输入 / HUD 信号
  → presentation/main.gd（组合根）
  → MechCommand → MechCommandQueue.submit
  → MechSimCore.validate_command / execute_command
  → 模拟状态变更 → state_changed
  → main 标脏 → _publish_state → SimCore.snapshot()
  → 各视图 present / present_*（只读）
```

三条硬边界：

1. **命令是唯一写入口**：UI 预览不授予免检权限，提交时 SimCore 重新校验；失败不得留下半笔付款或占位。
2. **模拟不依赖场景树或渲染节点**：`sim/`、`commands/`、`content/` 可独立于 `presentation/` 运行。
3. **共享 Resource 只保存不可变规则**：进度、HP、订单、倍率等运行时状态保存在 `MechEntityState` / `MechBuildingState` 实例。

## 2. 命令层 `commands/`

### 2.1 `MechCommand`（[sim_command.gd](../commands/sim_command.gd)）

短生命周期的意图表达，不记录、不持久化。

| 成员 | 类型 | 说明 |
| --- | --- | --- |
| `Type` | enum | 命令类型枚举，见 §2.3 |
| `type` | `Type` | 命令类型 |
| `payload` | `Dictionary` | 参数；构造时深拷贝 |
| `_init(command_type, command_payload = {})` | 构造 | 命令不做记录或回放 |

### 2.2 `MechCommandQueue`（[command_queue.gd](../commands/command_queue.gd)）

串行化所有请求，包括暂停期间发出的请求。

| 接口 | 说明 |
| --- | --- |
| `signal command_finished(command_type: int, result: Dictionary)` | 每条命令执行完毕时发出，携带结果副本 |
| `configure(executor: Callable)` | 注入执行器；实际接线为 `_sim.execute_command` |
| `submit(command: MechCommand) -> Dictionary` | 入队并驱动队列直至清空；返回**队首命令**的结果。排空期间的重入提交只入队，返回 `{ok: true, queued: true}` |
| 执行器签名 | `func(command: MechCommand) -> Dictionary` |

### 2.3 命令 payload 与结果契约

所有命令的通用结果：`{"ok": bool, "reason": String}`。失败时 `reason` 为面向玩家的中文原因；失败结果不会提交任何状态。成功时按类型附带下表字段。

| `MechCommand.Type` | payload | 成功结果附加字段 |
| --- | --- | --- |
| `SET_PAUSED` | `{paused: bool}` | 无 |
| `MOVE_ENTITY` | `{entity_id: int, target: Vector2}` | 校验结果含 `path: PackedVector2Array`；执行后剥离 |
| `RESET_SESSION` | `{}` | 无 |
| `PLACE_BUILDING` | `{building_id: StringName, origin: Vector2i}` | `entity_id`, `origin`, `cost` |
| `PLACE_WALL_LINE` | `{cells: Array[Vector2i]}` | `placed: int`, `skipped: int`, `cost`；固定下装甲墙 |
| `CANCEL_CONSTRUCTION` | `{entity_id: int}` | `refund: Dictionary` |
| `DEMOLISH` | `{entity_id: int}` | `clearing: bool`（清基座）, `refund` |
| `CANCEL_DEMOLISH` | `{entity_id: int}` | `was_clearing: bool` |
| `TOGGLE_REPAIR` | `{entity_id: int}` | 无 |
| `QUEUE_UNIT` | `{factory_id: int, unit_id?: StringName}` | `ticket: int` |
| `CANCEL_PRODUCTION` | `{factory_id: int, ticket: int}` | `refund` |
| `SET_RALLY` | `{factory_id: int, cell: Vector2i}` | 无 |
| `ISSUE_UNIT_ORDER` | `{ids: Array[int], kind: &"move"或&"attack_move"或&"attack", goal: Vector2, target_id?: int}` | `count: int`, `kind` |
| `LOAD_SCENARIO` | `{settings: MechFoundationSettings}` | `scenario: String` |
| `REBUILD` | `{entity_id: int}` | `entity_id`, `cost` |
| `REPAIR_ALL` | `{}` | `count: int` |
| `UPGRADE_BUILDING` | `{entity_id: int}` | `entity_id`, `cost` |
| `CANCEL_UPGRADE` | `{entity_id: int}` | `refund` |
| `CONFIGURE_DISPATCH_REGION` | `{cells: Array[Vector2i], budget_cap: Dictionary, region_id?: int, name?: String, enabled?: bool}` | `region_id: int`（新建或更新） |
| `REQUEST_FINAL_WAVE` | `{}` | `final_wave: bool` |
| `GARRISON_UNIT` | `{unit_id: int}` | `building_id: int` |
| `UNGARRISON_UNIT` | `{building_id: int}` | `ejected: int` |
| `ACCEPT_CONTRACT` | `{building_id: int}` | `unit_id: StringName` |
| `CANCEL_CONTRACT` | `{building_id: int}` | `refund` |
| `DELETE_DISPATCH_REGION` | `{region_id: int}` | `region_id` |

校验阶段的扩展结果：

- `PLACE_BUILDING` / `PLACE_WALL_LINE` 返回建造预览对象：`ok`, `reason`, `cells: Array[{cell, ok, reason}]`, `origin`, `footprint`, `cost`, `building_id`, `mineral_id`, `environment_energy`, `environment_power`, `collection_bounds`, `conflict_cells`；墙线另有 `planned_count`, `skipped_count`, `line: true`，执行器再加 `origins`。
- `ISSUE_UNIT_ORDER` 返回编队计划：`ids`, `kind`, `goal`, `target_id`, `paths: {entity_id: PackedVector2Array}`, `formation`（含槽位、队心与到达朝向）。
- `UPGRADE_BUILDING` 返回 `cost`。
- `GARRISON_UNIT` 返回进场计划：`entry: Vector2i`, `path: PackedVector2Array`, `building_id: int`。

## 3. 内容层 `content/`

七类 Resource，全部只保存不可变规则；实例运行时状态在 `sim/`。目录布局：

```text
content/development_128.tres     唯一正常配置（MechFoundationSettings）
content/unit_balance.json        集中单位/敌种数值表（运行时覆盖）
content/maps/                    MechMapDefinition
content/buildings/               MechBuildingDefinition（含升级形态）
content/units/                   MechUnitDefinition（JSON 缺失时的回退）
content/enemies/                 MechEnemyDefinition（JSON 缺失时的回退）
content/recipes/                 MechAlloyRecipe
content/build_menu_catalog.json  仅分类/展示，不是规则来源
```
`content/balance_catalog.gd` 的 `MechBalanceCatalog.apply(settings)` 在 `SimCore.configure` 开始时读取 JSON、构建定义对象并写入 `settings.unit_definitions` / `settings.enemy_definitions`；JSON 缺省字段沿用 Resource 默认值。

### 3.1 `MechBuildingDefinition`（[building_definition.gd](../content/building_definition.gd)）

| 字段组 | 字段 |
| --- | --- |
| 身份与占地 | `building_id`, `display_name`, `footprint`, `level`, `tech_level`, `is_core`, `buildable` |
| 造价与施工 | `cost`, `construction_seconds`, `max_hp`, `refund_ratio`, `demolition_seconds`（保留字段） |
| 供给与占用 | `capacity_cost`, `capacity_provided`, `capacity_system_reserved`, `power_cost`, `power_provided`, `cooling_cost`, `cooling_provided`, `income_per_minute` |
| 采集与加工 | `mined_resource`, `extraction_per_minute`, `alloy_recipe` |
| 覆盖与视野 | `coverage_radius`, `sight_radius`, `radar_warning_seconds` |
| 生产 | `produced_units: Array[StringName]`, `queue_limit` |
| 战斗与维修 | `attack_damage`, `attack_seconds`, `attack_range`, `splash_radius`, `repair_radius`, `repair_rate` |
| 特殊设施 | `requires_water`, `is_gate`, `trap_kind`, `trigger_radius`, `trap_damage`, `slow_multiplier`, `slow_seconds`, `one_shot`, `slow_fence_ratio` |
| 环境能源 | `environment_energy`（`none`/`wind`/`solar`）, `environment_output_multiplier`, `environment_output_cap` |
| 驻防与合同 | `garrison_capacity`, `garrison_range_bonus`, `contract_interval_seconds`, `contract_delivery_seconds`, `contract_price_multiplier` |
| 经济光环 | `aura_kind`（`none`/`mining`/`cooling`/`income`）, `aura_radius`, `aura_multiplier` |
| 升级链 | `required_tech_level`, `required_mainbrain_level`, `upgrade_to`, `upgrade_cost`, `upgrade_seconds` |
| 其他 | `infectable` |

接口：

| 方法 | 说明 |
| --- | --- |
| `is_wall_like() -> bool` | 是否墙类（装甲墙/合金墙），敌人寻路与攻击有特殊规则 |
| `supply_recovery() -> bool` | 是否供给恢复设施；算力超载时只放行这类零占容建筑 |
| `validation_error() -> String` | 全字段校验；空字符串表示有效 |
| `snapshot() -> Dictionary` | HUD/外部读取用普通字典快照 |

升级规则：`level >= 2` 的定义保持 `buildable = false`，只能经 `upgrade_to` 达成；升级链族根由 `MechConstructionSystem.family_root()` 计算，升级前后视为同种建筑，实体 ID 不变。

### 3.2 其他内容类型

| 类 | 文件 | 关键字段 | 接口 |
| --- | --- | --- | --- |
| `MechFoundationSettings` | [foundation_settings.gd](../content/foundation_settings.gd) | 种子、`simulation_hz`、地图、建筑/单位/敌种表、`balance_data_path`、开局资源/建筑/单位格、`probe_speed`/`probe_sight_radius`、波次触发模式、噪声半径、`ordinary_per_elite`、`max_elite_types`、`max_jammed_towers`、`total_waves`、`campaign_mode`、`final_wave_budget` | 无；由 `SimCore.configure` 消费 |
| `MechUnitDefinition` | [unit_definition.gd](../content/unit_definition.gd) | `unit_id`, `display_name`, `cost`, `production_seconds`, `capacity_cost`, `max_hp`, `damage`, `attack_seconds`, `attack_range`, `acquisition_range`, `move_speed`, `sight_radius` | `validation_error()`, `snapshot()` |
| `MechEnemyDefinition` | [enemy_definition.gd](../content/enemy_definition.gd) | 战斗：`max_hp`, `damage`, `damage_vs_building`, `attack_seconds`, `attack_range`, `move_speed`, `vision_radius`, `threat_cost`；波次：`stage_weights`, `elite`；能力：`charge_bonus`, `charge_linger_seconds`, `ignores_rough`, `prefers_towers`, `prefers_buildings`, `splash_radius`, `scavenge_radius`, `scavenge_armor_ratio`, `scavenge_max_armor`, `jam_*`, `boost_*`, `shelter_*`, `passes_walls`, `evasion_chance`, `frenzy_radius`, `frenzy_seconds`, `frenzy_speed_bonus`, `frenzy_damage_bonus`, `marches_to_core` | `validation_error()`, `building_damage()`, `snapshot()` |
| `MechMapDefinition` | [map_definition.gd](../content/map_definition.gd) | `map_id`, `display_name`, `dimensions`, `playable_polygon`, `obstacle_rects`, `rough_rects`, `wind_cells`, `water_cells`, `mainbrain_origin/footprint`, `probe_cell`, `main_gate`, `flank`, `minerals` | `validation_error()`, `outline()`, `contains_cell()`, `playable_cells()`, `terrain_cells()`, `wind_mask()`, `water_mask()`, `wanderer_spawn_allowed()`, `terrain_snapshot()`, `mineral_snapshots()` |
| `MechMineralDefinition` | [mineral_definition.gd](../content/mineral_definition.gd) | `mineral_id`, `cell`, `resource_kind`（`metal_ore`/`fuel`/`crystals`）, `amount` | `snapshot()`（`assigned_to` 为模拟层占位字段） |
| `MechAlloyRecipe` | [alloy_recipe.gd](../sim/alloy_recipe.gd) | `recipe_id`, `cycle_seconds`, `fuel_cost`, `metal_cost`, `alloy_output`, `power_output` | `validation_error()`, `snapshot()` |

## 4. 模拟层 `sim/`

### 4.1 会话核心 `MechSimCore`（[sim_core.gd](../sim/sim_core.gd)）

权威会话核心。命令先提交全部状态，然后才通知视图。

| 接口 | 说明 |
| --- | --- |
| `signal state_changed` | 任一权威状态变化后发出；表现层只据此标脏 |
| `profiling_enabled: bool` | 是否收集 `--perf` 阶段计时 |
| `configure(settings: MechFoundationSettings) -> bool` | 装配全局设置并重置开局；失败进入错误态 |
| `shutdown()` | 等待敌人在途 Worker 任务结束并清空注册表 |
| `execute_command(command: MechCommand, cancel_motion: bool = true) -> Dictionary` | 校验 → 提交 → 统一刷新 → 广播；`cancel_motion` 为假时保留在途 RVO 批次（自动内部命令使用） |
| `validate_command(command: MechCommand) -> Dictionary` | 纯校验，不产生任何变更 |
| `advance_one_tick()` | 推进一个固定步长 tick；暂停或已结束时不推进 |
| `snapshot() -> Dictionary` | 整局只读快照，结构见 §4.2 |
| `map_snapshot() -> Dictionary` | 地形/占用/覆盖/水面/风声快照 + 地图名称、主脑与地标 |
| `inspect_cell(cell: Vector2i) -> Dictionary` | 单格信息；未探索格只返回“未探索” |
| `building_at(cell: Vector2i) -> Dictionary` | 该格建筑快照；未探索或无建筑返回空字典 |
| `preview_footprint(origin, footprint) -> Dictionary` | 逐格地形/占用预览 |
| `preview_build(id: StringName, origin: Vector2i) -> Dictionary` | 建造预览（含前置、矿点、环境评分与经济预留） |
| `preview_wall_line(cells: Array[Vector2i]) -> Dictionary` | 墙线批量预览，前序可下单段会扣减虚拟钱包 |
| `building_action_error(type: MechCommand.Type, entity_id: int) -> String` | 建筑操作的中文失败原因，空串表示可执行 |
| `damage_building(entity_id: int, amount: int) -> Dictionary` | **敌方对建筑伤害的唯一权威入口**；含交战、摧毁、感疫与废墟结算 |
| `spawn_diagnostic_enemy(enemy_id, position) -> int` | 诊断入口，正常玩家命令不可用 |
| `seed_diagnostic_population(desired: int, seed_value: int = 20261110) -> Dictionary` | 压力入口的可复现初始负载 |
| `consume_profile() -> Dictionary` | 取走并清空阶段计时数据 |
| `session_ended() -> bool` / `is_paused() -> bool` / `scenario_name() -> String` / `tick_rate() -> int` | 会话状态查询 |

单个 tick 的固定顺序：收入 → 施工 → 生产 → 敌我战斗 → 炮塔 → 移动 → 结算。暂停只冻结时钟，命令仍校验、付款和更新意图。

### 4.2 快照结构

`SimCore.snapshot()` 顶层键：

| 键 | 内容 |
| --- | --- |
| `clock` | `{tick, tick_rate, elapsed_seconds, paused}` |
| `entities` | 可见实体快照数组；驻防单位不在此列，建筑快照会合并到对应实体条目 |
| `garrisoned_unit_ids` | `Array[int]`，仅用于编队存活性判断 |
| `economy` | 账本与供给余量，见下表 |
| `minerals` | 已探索矿点：`{mineral_id, cell, resource_kind, remaining, initial_amount, assigned_to, visible}` |
| `vision` | `{dimensions, cells: PackedByteArray(State), revision}` |
| `repair_all` | `{ok, reason, count}` |
| `scenario` | 场景名 |
| `unit_catalog` | `{unit_id: unit snapshot}` |
| `catalog` | 可下单建筑目录；每项是建筑定义快照 + `unavailable_reason` |
| `probe_id` | 诊断校验实体 ID，正常开局为 0 |
| `frenzies` | 可见的煽动者死亡光环 `{position, radius, ticks}`；离开光环即失去增益 |
| `alloy_processing` | `{ever_produced_alloy, produced_alloy}` |
| `dispatch` | `{generation, regions: Array[Dictionary]}`；表现层另加 `selected_region_id` |
| `mainbrain_id` | 主脑实体 ID |
| `generation` | 会话代号；重开后递增，表现层据此重置选择 |
| `session` | `{outcome, ended, reason, duration_seconds, wave_number, final_phase}` |
| `threat` | 波次导演状态 + `final_phase`；雷达提前时附加 `radar_warning`, `radar_lead_seconds`, `radar_edge_name`, `radar_wave_number`, `radar_seconds_remaining` |
| `alert` | 最近一次告警 `{sequence, text}` 或空字典 |
| `map_revision` / `coverage_revision` | 地形/覆盖修订号，用于惰性重建 |
| `map_name` | 地图显示名 |

`economy` 子结构：

```text
resources: {coins, metal_ore, fuel, alloy, crystals}
coins, capacity_used, capacity_supply, capacity_total, capacity_system_reserved
cooling_reserved, cooling_supply, cooling_free, cooling_deficit
power_reserved, power_supply, power_free, income_rate
overloaded, power_deficit
production_per_minute: {资源ID: int}
unit_capacity, queued_capacity
```

实体条目字段（`MechEntityState.snapshot()`）：

```text
id, kind, name, position, target, has_order, footprint, path, is_unit, team, hp, max_hp,
is_enemy, enemy_id, elite, charge_ticks, speed_boost_ticks, scavenge_armor, jam_target_id, frenzy_ticks,
order, order_goal, attack_target_id, facing, arrival_facing, has_arrival_facing,
formation_id, formation_center, formation_offset, shot_ticks, shot_target,
capacity_cost, damage, attack_range
```

建筑条目在实体字段之外合并 `MechBuildingState.snapshot()`：

```text
building_id, name, footprint, cost, max_hp, 各供给/战斗/功能字段（同建筑定义）
entity_id, origin, is_building, phase, status, hp, paid_cost,
jam_ticks, jam_immunity_ticks, build_progress, demolition_progress, demolition_seconds,
refund, repairing, threatened, powered, repair_waiting_for_materials,
repair_material_remainder, income/extraction/cooling_multiplier_percent,
environment_power, processing{active,elapsed,total,paid,power,progress},
upgrade{active,target,target_name,elapsed,total,paid,progress},
waiting_for_clearance, rebuild_cost, shot_ticks, shot_target
```

`SimCore` 额外附加：`family_id`、`mineral`、`upgrade_error`、`production`、`garrison_count`、`contract{offer,delivery_seconds,unit_id,accept_error}`；生产建筑附加 `unit_options: Array[快照]` 与 `production_error`；墙类附加 `connections: int`；受偏转场保护的敌人附加 `sheltered: true`。

`map_snapshot()` 即 `MechGridState.snapshot()`：`dimensions`, `terrain`, `playable`, `outline`, `occupancy`, `coverage`, `wind`, `water`, `rough_weight`, `revision`，另加 `name`, `mainbrain_origin`, `mainbrain_footprint`, `main_gate`, `flank`。

### 4.3 时钟与实体

| 类 | 文件 | 职责 | 主要公开接口 |
| --- | --- | --- | --- |
| `MechSimulationClock` | [simulation_clock.gd](../sim/simulation_clock.gd) | 固定步长 tick 计数；暂停不影响场景树/输入 | `configure(tick_rate)`, `reset()`, `set_paused(value)`, `is_paused()`, `advance() -> bool`, `step_seconds()`, `snapshot()` |
| `MechEntityState` | [entity_state.gd](../sim/entity_state.gd) | 纯逻辑实体状态，无 Node/渲染资源 | 字段分五组：身份与位置、指令与战斗、减速/控制、驻防、编队与路径；方法 `set_move_path()`, `next_waypoint()`, `preferred_velocity()`, `finish_path_if_arrived()`, `face_direction()`, `face_arrival()`, `apply_slow()`, `advance_slow()`, `snapshot()` |
| `MechEntityRegistry` | [entity_registry.gd](../sim/entity_registry.gd) | 稳定自增 ID、批量原生移动提交 | `signal movement_finished`（整批一次）；`clear()`, `create(kind, display_name, position, rvo_speed, footprint) -> int`, `can_move()`, `get_entity()`, `all()`, `mobile_space_free()`, `position_of()`, `remove()`, `stop()`, `teleport()`, `set_move_path()`, `set_friendly_pass()`, `step(seconds, grid)`, `cancel_pending_motion()`, `suspend_motion()`, `movable_snapshots()`, `snapshots()` |

`MechEntityState` 关键约定：`rvo_speed > 0` 的实体才进入原生 RVO 求解器；`team = 1` 为玩家、`team = 2` 为敌人；`order` 取值 `idle` / `move` / `attack_move` / `attack`；`march_zone` 为稳定局部导航区，`z` 分量区分常规/穿墙规则。

### 4.4 网格、寻路与避障

| 类 | 文件 | 职责 | 主要公开接口 |
| --- | --- | --- | --- |
| `MechGridState` | [grid_state.gd](../sim/grid_state.gd) | 地形/占用/覆盖/风/水五个权威层；独立修订号 | `configure(definition)`, `dimensions()`, `playable_cell_count()`, `revision()`, `terrain_revision()`, `coverage_revision()`, `coverage_changes_since()`, `navigation_changes_since()`, `navigation_copy(ignore_rough)`, `contains()`, `point_inside()`, `boundary_cells()`, `boundary_side()`, `terrain_at()`, `occupant_at()`, `is_covered()`, `is_wind()`, `is_water()`, `footprint_covered()`, `recompute_coverage(buildings)`, `release()`, `set_pass_through()`, `is_walkable()`, `set_friendly_pass()`, `is_pass_through()`, `enemy_blocker_at()`, `mobile_position_clear()`, `mobile_segment_clear()`, `movement_weight()`, `terrain_line_clear()`, `inspect_cell()`, `preview_footprint()`, `try_occupy()`, `snapshot()`, `terrain_build_error()` |
| `MechGridNavigation` | [grid_navigation.gd](../sim/grid_navigation.gd) | 原生 `AStarGrid2D` 加权寻路；增量更新脏格 | `set_friendly_pass(enabled)`, `rebuild(grid, ignored_occupants, ignore_rough)`, `find_path(from, target_cell)`, `find_path_to_point(from, target)`, `segment_clear(from, to)` |
| `MechCrowdNavigation` | [crowd_navigation.gd](../sim/crowd_navigation.gd) | Godot 原生 RVO2 适配器；无本地转向求解 | `signal velocities_ready(request_id, velocities)`；`set_friendly_pass()`, `request(entities, preferred, grid) -> int`, `cancel_pending()`, `suspend()`, `remove(id)`, `teleport(id, position)`, `dispose()` |
| `MechMarchField` | [march_field.gd](../sim/march_field.gd) | 纯地形积分场（4 连通积分 + 8 邻域方向）；静态场不因占用/HP 重建 | `rebuild(grid, goal)`, `rebuild_local(grid, bounds, sources, source_values, ignored_occupants)`, `cost_at()`, `source_at()`, `blocks_at()`, `is_reachable()`, `flow_at()` |
| `MechFormationPlanner` | [formation_planner.gd](../sim/formation_planner.gd) | 命令时刻的编队槽位规划；适配 vendor `RTSFormation` | `plan(members, goal, grid, navigation) -> {ok, reason, paths, slots, center, facing}` |

`MechCrowdNavigation.request()` 的返回值为请求代号：无待处理实体返回 0；结果经 `velocities_ready` 整批返回。`cancel_pending()` 自增代号使旧回调失效。

### 4.5 建造、经济与生产

| 类 | 文件 | 职责 | 主要公开接口 |
| --- | --- | --- | --- |
| `MechConstructionSystem` | [construction_system.gd](../sim/construction_system.gd) | 共享放置规则 + 各建筑独立生命周期 | `configure(definitions) -> String`, `clear()`, `definition(id)`, `family_root(id)`, `get_building(entity_id)`, `all()`, `add(entity_id, id, origin, hz, completed)`, `remove()`, `catalog(economy)`, `preview_placement(...)`, `preview_wall_line(...)`, `advance(try_clear_footprint) -> {completed, demolished}` |
| `MechBuildingState` | [building_state.gd](../sim/building_state.gd) | 单建筑进度、HP、拆除、维修、升级、驻防、合同、冶炼运行时 | `Phase` 枚举 `CONSTRUCTING/OPERATING/DEMOLISHING/RUINED`；常量 `REBUILD_COST_RATIO = 0.5`, `THREAT_RADIUS = 6.0`；`configure()`, `operating()`, `refresh_definition_ticks()`, `advance_construction()`, `refund()`, `rebuild_cost()`, `mark_ruined()`, `reset_repair_state()`, `convert_repair_denominator()`, `cycle_refund()`, `upgrade_refund()`, `status()`, `snapshot()` |
| `MechEconomySystem` | [economy_system.gd](../sim/economy_system.gd) | 整数钱包与容量/电力/冷却预留；短缺不冻结既有设施 | `repair_authorized: Callable`, `repair_paid: Callable`；`reset()`, `coins()`, `balance()`, `spend_error(amount, available)`, `try_spend(amount)`, `credit(amount)`, `recompute(buildings, grid, unit_capacity, queued_capacity)`, `contract_error()`, `reservation_error()`, `upgrade_error()`, `production_error()`, `advance_income()`, `advance_repairs()`, `snapshot()` |
| `MechResources` | [resources.gd](../sim/resources.gd) | 五项稳定资源 ID 的纯静态工具 | 常量 `KEYS`, `NAMES`, `WORTH`；`empty()`, `copy()`, `single()`, `valid()`, `mineable()`, `text()`, `add()`, `subtract()`, `scaled()`, `worth()` |
| `MechMineralSystem` | [mineral_system.gd](../sim/mineral_system.gd) | 有限矿点；下单时预留、提交时绑定 | `reset(definitions)`, `at(cell)`, `deposit(id)`, `snapshots()`, `placement(rules, origin)`, `bind(id, entity_id)`, `release(entity_id)`, `advance(buildings, economy, hz)`, `has_produced(resource)`, `production_rate(buildings)` |
| `MechAlloyProcessing` | [alloy_processing.gd](../sim/alloy_processing.gd) | 热能冶炼周期；燃料开局原子扣款 | `ever_produced_alloy: bool`, `produced_alloy: int`；`reset()`, `advance(buildings, economy, hz) -> bool` |
| `MechEnvironmentEnergy` | [environment_energy.gd](../sim/environment_energy.gd) | 风/光集能区计分与同类型预留 | 常量 `EXTENSION = 3`, `WIND_CAP = 18`, `SOLAR_CAP = 20`；`clear()`, `collection_bounds()`, `conflicts()`, `reserve(entity_id, energy_type, origin, footprint) -> bool`, `release(entity_id)`, `score(energy_type, origin, footprint, grid, vision, multiplier, cap) -> int` |
| `MechDispatchModel` | [dispatch_model.gd](../sim/dispatch_model.gd) | 纯数据区域授权与预算台账，不改世界/钱包/实体 | `reset()`, `generation()`, `create_region(cells, budget_cap, name, enabled)`, `remove_region()`, `has_region()`, `update_region()`, `set_enabled()`, `can_retry()`, `note_failure()`, `note_success()`, `commit(id, task_id, cost, generation)`, `rename_task()`, `settle()`, `release()`, `task_ids()`, `set_budget_cap()`, `set_failure()`, `region_ids()`, `snapshot()`, `can_consume()`, `consume()`, `refund_spent()` |
| `MechProductionSystem` | [production_system.gd](../sim/production_system.gd) | 预付费、占容预留、各工厂独立队列 | `order_finished: Callable(ticket, refund)`；`clear()`, `register_factory()`, `reserved_capacity()`, `order_error()`, `enqueue(factory_id, rules, hz) -> ticket`, `has_ticket()`, `cancel(factory_id, ticket) -> refund`, `remove_factory(factory_id, refund_orders)`, `set_rally()`, `snapshot(factory_id)`, `advance(construction, spawn) -> bool` |

`MechBuildingState` 的维修约定：每点 HP 的材料消耗以 `分子 / (4*max_hp)` 的分数保留；“受击建筑在 `THREAT_RADIUS` 内仍有敌人时保持交战，维修暂停”。

### 4.6 单位、炮塔与敌军

| 类 | 文件 | 职责 | 主要公开接口 |
| --- | --- | --- | --- |
| `MechUnitSystem` | [unit_system.gd](../sim/unit_system.gd) | 玩家指令、编队应用与单位战斗循环 | `combat_noise: Callable`；`create(registry, rules, cell) -> int`, `capacity_used(registry)`, `plan_order(ids, kind, goal, target_id, registry, grid, navigation)`, `apply_order(plan, registry)`, `spawn(building, rally, rules, registry, grid, navigation) -> bool`, `advance(registry, grid, navigation, hz, vision) -> {enemy_hits}` |
| `MechTowerSystem` | [tower_system.gd](../sim/tower_system.gd) | 运行中炮塔自动开火；扫描摊销到冷却结束时刻 | `combat_noise: Callable`；`advance(registry, buildings, hz, grid, vision) -> Array[命中]` |
| `MechEnemyAbilities` | [enemy_abilities.gd](../sim/enemy_abilities.gd) | 拾荒护甲池、煽动者死亡光环、单塔干扰/免疫/提速与来源失效 | `prepare(registry)`, `note_death(dead, hz)`, `armor(entity) -> float`, `frenzy_snapshots() -> Array[Dictionary]`, `release_source(id, buildings)`, `validate_links(registry, buildings, grid)`, `advance(registry, buildings, grid, hz, max_jammed)` |
| `MechEnemySystem` | [enemy_system.gd](../sim/enemy_system.gd) | 机潮行军/接敌；全局静态场 + 局部场；空间桶目标查询 | `profiling_enabled: bool`；`configure_noise(emitter)`, `reset(grid, goal, buildings)`, `shutdown()`, `create(registry, rules, position, ambient = false) -> int`, `advance(registry, grid, navigation, buildings, hz, noises, vision) -> {dead_units, building_hits}` |
| `MechThreatSystem` | [threat_system.gd](../sim/threat_system.gd) | 游荡种群、噪声事件、感疫转化 | `configure(definitions, settings) -> String`, `reset(grid, map, active, hz)`, `advance(buildings) -> Array[生成请求]`, `noises()`, `infect(cost, position) -> Array[生成请求]`, `note_combat()`, `note_construction()`, `note_operation()`, `note_movement()` |
| `MechWaveDirector` | [wave_director.gd](../sim/wave_director.gd) | 波次相位、预算编成、边缘流式投放、战役终波 | `configure(settings) -> String`, `reset(grid, map, active, hz)`, `advance(grid, buildings, entities) -> Array[生成请求]`, `request_final_wave() -> bool`, `set_campaign_stage(stage)`, `state() -> Dictionary`, `exhausted() -> bool` |

生成请求统一为 `{enemy_id: StringName, position: Vector2, delay: int}`，由 SimCore 交给 `MechEnemySystem.create()`。伤害与死亡统一由 SimCore 结算：单位/炮塔/驻军/陷阱只返回命中结果，不直接扣血。

### 4.7 视野 `MechVisionSystem`（[vision_system.gd](../sim/vision_system.gd)）

| 接口 | 说明 |
| --- | --- |
| `State` 枚举 | `UNEXPLORED / EXPLORED / VISIBLE` |
| `reset(grid)` | 按网格尺寸重置全部视野状态 |
| `explored_revision() -> int` | 已探索修订号，单调递增 |
| `consume_explored_changes() -> Array[Vector2i]` | 取走自上次消费以来新探索的格子；消费后清空 |
| `update(grid, registry, buildings, probe_radius) -> bool` | 汇总视野源并重建可见性；返回可见性是否变化（决定是否上传迷雾纹理） |
| `state_at(cell) -> State` / `is_visible(position) -> bool` | 查询；战斗锁定使用 `is_visible` |
| `snapshot() -> Dictionary` | `{dimensions, cells: PackedByteArray, revision}` |

规则：探索覆盖每个视野源的半径、**不受遮挡影响**；实时可见额外要求地形 LOS；通视脚印按源缓存，格内移动不会重建可见性。

## 5. 表现层 `presentation/`

### 5.1 组合根 `main.gd`

无 `class_name`，由唯一战场入口 `scenes/main_3d.tscn` 使用。职责：

1. 装配 `MechSimCore`、`MechCommandQueue`、两个输入控制器与全部视图；
2. 物理帧按 `simulation_hz` 调用 `advance_one_tick()`；
3. 监听 `state_changed` 只标脏，每渲染帧至多构造一次快照；
4. 路由全局快捷键和 HUD 信号，保持建造/选择/相机的事件优先级；
5. 发布同一份快照给视图与选择控制器，协调建造预览与提示。

输入控制器为组合根持有的 RefCounted，不额外注册 `_input`，不会改变场景树传播顺序：

| 类 | 文件 | 主要接口 |
| --- | --- | --- |
| `MechSelectionController` | [selection_controller.gd](../presentation/selection_controller.gd) | `configure(sim, commands, hud, world, camera, viewport)`；`update_state(state, generation_changed)`、`left_click(event)`、`right_click()`、`handle_drag_event(event)`、`cancel_drag()`、`handle_group(number, store)`、`selected_units()`、`select_building(entity_id, origin)`、`select_starting_units()`、`present_selection()`；只读 `selected_ids`，复用 MechSelectionState |
| `MechBuildController` | [build_controller.gd](../presentation/build_controller.gd) | `configure(sim, commands, hud, world, camera, coverage, viewport, window)`；`request(id, catalog)`、`cancel()`、`follow_mouse(event)`、`handle_key(key)`、`begin_wall(event)`、`handle_wall_event(event)`、`cancel_wall_drag()`、`place_at(map_position)`、`present_cursor(selected_cell, settings_open)` |

两个控制器的 `cursor_changed` 信号由 main 接线后刷新光标；控制器不持有 main。选择使用最近发布快照，指令仍经同一 CommandQueue 提交；失焦/离窗直接取消控制器中的未完成手势，重开/新 generation 清除选择和编队时序。未确定的模拟功能暂不拆分。

它向视图约定的方法集合（视图按需实现，缺省方法由 当前3D视图实现）：

| 方法 | 用途 |
| --- | --- |
| `configure(settings)` | 仅 `MechFoundationView3D`，注入建筑定义用于模型外观 |
| `present_map(map_state)` | 地形/占用/覆盖/水面/风声等静态地图快照 |
| `present_vision(vision)` | 视野快照，更新迷雾与地标解锁 |
| `present(state)` | 整局快照，重建实体显示 |
| `present_selection(ids: Array[int])` | 选择高亮 |
| `present_cursor(hover, selected, preview, visible_cursor)` | 建造光标与逐格预览 |
| `present_camera(polygon)` | 镜头取景框（小地图） |
| `present_zoom(factor)` | 缩放读数 |
| `present_state(state)` | HUD 主面板 |
| `present_units(units: Array[Dictionary])` | 选中单位详情 |
| `present_cell(info, preview)` | 单元格信息 |
| `present_selection(building, errors)` | 选中建筑详情 |
| `present_build(id)` | 当前建造选择高亮 |
| `present_drag(rect, active)` | 框选手势 |
| `feedback(message, failed)` | 反馈条 |
| `pick_entity/pick_unit/pick_building(point) -> int` | 拾取 |
| `blocks_point(point)` / `selection_bounds(start, end)` / `battle_view_rect()` | HUD 面板占位与战场矩形 |

### 5.2 战场与HUD视图

| 类 | 文件 | 职责 | 主要接口 |
| --- | --- | --- | --- |
| `MechPortraitView2D` | [portrait_view_2d.gd](../presentation/portrait_view_2d.gd) | HUD单对象肖像，保留既有二维外观 | `present(entity)`；不包含战场拾取/路径/光标/地图预览 |
| `MechFoundationView3D` | [foundation_view_3d.gd](../presentation/foundation_view_3d.gd) | 3D 默认：共享 Mesh 实例、BVH 射线拾取、血条/范围/提示 | `configure(settings)`, `present()`, `present_selection()`, `present_cursor()`, `pick_entity()`, `pick_unit()`, `pick_building()` |
| `MechTerrainView3D` | [terrain_view_3d.gd](../presentation/terrain_view_3d.gd) | 3D 地形静态分块网格；复用多边形裁剪/三角化 | `present_map()`, `present_vision()` |
| `MechFogView3D` | [fog_view_3d.gd](../presentation/fog_view_3d.gd) | 三态迷雾纹理，供地面与模型材质共同采样 | `material(ground = false) -> ShaderMaterial`, `preview_material()`, `present(vision, generation, outline)` |
| `MechCoverageView3D` | [coverage_view_3d.gd](../presentation/coverage_view_3d.gd) | 建造时的供电覆盖；只显示已探索格 | `present_map(map_state)` |
| `MechBattleOverlay3D` | [battle_overlay_3d.gd](../presentation/battle_overlay_3d.gd) | 集中绘制屏幕血条与状态，不逐实体建 Control | `present(state, selected: Array[int], bounds: Dictionary)` |
| `MechInstanceBatches3D` | [instance_batches_3d.gd](../presentation/instance_batches_3d.gd) | 显示实例批管理，无实体逻辑 | `present(groups, shared_material)`, `clear()`, `static append(groups, key, mesh, transform, color)` |
| `MechModelCatalog3D` | [model_catalog_3d.gd](../presentation/model_catalog_3d.gd) | 原生几何合并为共享 Mesh；覆盖建筑/单位/敌种 | `model(entity: Dictionary) -> Mesh` |
| `MechSelectionState` | [selection_state.gd](../presentation/selection_state.gd) | 纯客户端选择与编组 | `ids`, `groups`；`reset()`, `select(next, additive, toggle)`, `reconcile(entities, garrisoned_unit_ids)`, `store_group(key)`, `recall_group(key)` |
| `MechIsoGeometry` | [iso_geometry.gd](../presentation/iso_geometry.gd) | 2D 等距投影（仅小地图与肖像使用） | `project()`, `unproject()`, `cell_at()`, `footprint_polygon()`, `map_bounds()` |

### 5.3 镜头适配器

`MechMapCamera3D`（Camera3D）提供唯一战场镜头接口，`main.gd` 不依赖具体投影：

| 接口 | 说明 |
| --- | --- |
| `configure_map(map_state)` | 地图尺寸、轮廓与主脑焦点 |
| `screen_to_map(point) -> Vector2` / `map_to_screen(point, height = 0) -> Vector2` | 屏幕 ↔ 逻辑地图坐标 |
| `map_point_on_screen(point) -> bool` | 逻辑点是否在可视区 |
| `visible_map_polygon() -> PackedVector2Array` | 镜头取景多边形（供小地图） |
| `zoom_factor() -> float` | 当前缩放 |
| `focus_map(point)` / `focus_mainbrain()` / `fit_map()` | 聚焦与总览 |
| `set_play_area(rect)`/ `set_external_gesture(active)` | 战场矩形与外部手势占用 |
| `handle_event(event) -> bool` | 中键拖拽/滚轮缩放；返回是否消费 |

可调属性：`pan_speed_factor`, `zoom_speed_factor`, `edge_scroll_enabled`, `input_blocked`, `keyboard_pan_blocked`。

### 5.4 HUD、菜单与小地图

`MechMapHud`（[map_hud.gd](../presentation/map_hud.gd)）只发意图信号，全部授权判定留在模拟层：

```text
pause_requested, restart_requested, focus_requested, fit_requested,
build_requested(id), build_cancelled,
building_action_requested(action, entity_id),
production_requested(factory_id, unit_id), production_cancelled(factory_id, ticket),
upgrade_requested(entity_id), upgrade_cancelled(entity_id),
settings_requested, minimap_focus_requested(map_position),
dispatch_region_selected(cells), repair_all_requested
```

HUD 读取接口：`present_map()`, `present_state()`, `present_camera()`, `present_zoom()`, `present_build()`, `present_cell()`, `present_selection(building, errors)`, `present_units()`, `present_drag()`, `feedback()`；布局辅助：`blocks_point()`, `selection_bounds()`, `battle_view_rect()`, `dismiss_dialogs()`, `request_demolition()`；小地图全屏：`begin_dispatch_region_selection()`, `toggle_minimap_fullscreen()`, `set_minimap_fullscreen()`, `is_minimap_fullscreen()`。

| 类 | 主要接口 |
| --- | --- |
| `MechMinimapView` | `signal focus_requested(map_position)`, `signal region_selected(cells)`；`present_map()`, `present_state()`, `present_camera()`, `set_region_mode(enabled)` |
| `MechBuildMenu` | `signal build_requested(id)`, `signal cancel_requested`, `signal focus_requested`；`present_catalog(catalog: Array, ended: bool)`, `present_build(id)`, `reset_menu()` |
| `MechSettingsMenu` | `signal close_requested`, `signal settings_applied(preferences)`；`preferences() -> Dictionary`, `is_open()`, `open()`, `close()`；写盘路径 `user://settings.cfg`，默认值见 `DEFAULTS` |

### 5.5 内容工具与着色器

| 入口 | 文件 | 用途 |
| --- | --- | --- |
| 模型目录场景 | [model_gallery_3d.gd](../presentation/model_gallery_3d.gd) + `scenes/model_gallery_3d.tscn` | 展示全部工程模型；不运行模拟、不作为性能验证 |
| 地图总览场景 | [map_overview_3d.gd](../presentation/map_overview_3d.gd) + `scenes/development_map_overview.tscn` | 显示真实地图数据与地标；不创建模拟、不修改迷雾 |
| 迷雾着色器 | [map_fog_3d.gdshader](../presentation/map_fog_3d.gdshader) | uniforms: `fog_cells`, `map_dimensions`, `ground_grid`；三态值 `<0.25` 黑雾、`<0.75` 探索、`>=0.75` 可见 |
| 建造预览着色器 | [build_preview_3d.gdshader](../presentation/build_preview_3d.gdshader) | uniforms: `fog_cells`, `map_dimensions`, `preview_tint`；未探索格丢弃 |

## 6. 第三方模块 `vendor/`

| 类 | 文件 | 接口 |
| --- | --- | --- |
| `Steering` | [steering.gd](../vendor/crusade/steering.gd) | 纯世界空间局部避让向量数学：`static separation(pos, neighbors, radius) -> Vector2`, `static desired_velocity(flow_dir_world, max_speed) -> Vector2`, `static combine(flow_desired, separation_vec, flow_weight, separation_weight, max_speed) -> Vector2`；常量 `DEFAULT_SEPARATION_RADIUS = 28.0`, `EPSILON = 0.0001` |
| `RTSFormation` | [rts_formation.gd](../vendor/rts_advanced_lite/rts_formation.gd) | `static box(from, target, count, spacing = 2.0) -> Array[Vector3]`, `static line(...)`, `static assign(unit_positions, slots) -> Array[int]` |

来源与许可证见各目录 `README.md` / `LICENSE`；`sim/formation_planner.gd` 是运行时适配器。

## 7. 验证脚本 `validation/`

`vision_checks.gd` 是不带 `class_name` 的 `SceneTree` 入口：

```powershell
godot --headless --path . --script validation/vision_checks.gd
```

覆盖视野探索、遮挡、格内移动缓存、建筑视野、源移除与探索保留；失败以 `push_error("VISION CHECK FAILED: ...")` 输出并以非零码退出。它不是运行时模块，不进入主场景。

## 8. 接口扩展约定

1. **新增命令**：在 `MechCommand.Type` 加枚举 → `SimCore.validate_command` 加纯校验分支 → `execute_command` 提交 → 统一返回 `{ok, reason, ...}`；表现层只 `submit`，不得绕过校验直接改状态。
2. **新增建筑/单位/敌种**：优先只加 `content/` Resource；只有出现新的规则字段时才扩展定义类与对应系统，不把数值写进 `sim/`。
3. **新增视图**：实现所需的 `present_*` 方法并只消费快照；不得持有 `MechEntityState` / `MechBuildingState` 引用，也不得反写模拟。
4. **快照兼容**：`snapshot()` 只增不改语义；表现层必须容忍读取方未使用的键，但不得假定未文档化字段长期存在。
5. **失败语义**：任何跨层调用失败都返回 `{ok: false, reason: 中文}`；不要用抛出异常或空值静默失败。
6. **内部命名**：`_` 前缀接口可随时调整；外部代码只依赖本文列出的公开声明。
