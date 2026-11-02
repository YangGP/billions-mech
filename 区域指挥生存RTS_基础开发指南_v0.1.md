# 区域指挥生存 RTS：基础开发指南 v0.1

> 状态：可开工的最小开发规格（不是完整游戏设计文档）  
> 引擎：Godot 4.x 稳定版｜语言：GDScript｜画面：2D 等距视角｜目标平台：PC  
> 设计原则：**先做《亿万僵尸》式经济与自由建造，再加入区块视图；暂不做战斗和规划 AI。**

## 0. 本轮目标与范围

### 里程碑 M1：经济建设原型

玩家能够在固定等距地图上放置、预览、拆除建筑；建筑占地正确、不能重叠；资源按周期变化；建筑提供生产、人口或能源等效果；可持续扩建基地。

### 里程碑 M2：区块视图原型

在**同一个世界状态**上显示区块边界、建筑数量、资源产出和地块占用情况；点击区块查看统计，切换视图不影响模拟。

### 明确不做

战斗、敌方 AI、寻路、尸潮、自动施工、长期战略计划、多人、随机地图、完整科技树、美术打磨。将这些保留在后续设想中，不列入 M1/M2 验收。

---

## 1. 核心技术决定

1. **二维逻辑网格是唯一空间真相。** 建筑占地、邻近关系、区域归属使用 `Vector2i` 格子坐标，不使用贴图像素或碰撞体来判断能否建造。
2. **等距只是一种投影。** 使用 Godot `TileMapLayer` + `TileSet` 的等距菱形瓦片。游戏规则仍使用二维格子。
3. **数据与显示分离。** 建筑定义与建筑实例独立于 Sprite；HUD 只读模型，按钮通过系统方法修改模型。
4. **手动建造优先做完整。** 规划层未来也应调用同一套建筑校验与施工接口。
5. **资源全局共享。** M1 不做区块独立库存。
6. **先固定地图和占地。** M2 的区块可先按逻辑格划为固定矩形；将来可换不规则形状。

参考 Godot 官方文档：
- TileMapLayer：https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html
- TileSet：https://docs.godotengine.org/en/stable/classes/class_tileset.html
- 使用 TileMaps：https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html

## 2. 开发环境与项目设置

- 选用 **Godot 4.x 的稳定版本**，整个原型阶段固定版本，不要边开发边升级主版本。
- 渲染器：先用 Compatibility 或默认适合 2D 的设置，不因少量静态建筑引入特殊渲染管线。
- 视口：先设 `1600 × 900`（或 `1280 × 720`）；缩放模式统一并测试窗口缩放。
- 输入映射：`camera_left/right/up/down`（WASD）、`camera_zoom_in/out`（鼠标滚轮，可使用输入事件）、`cancel_action`（Esc）、`toggle_region_view`（Tab）、`pause_game`（Space）。
- 美术占位：地面菱形 128×64 像素；建筑图片可以用彩色矩形/简单等距盒子代替。
- 建议使用 Git，首次提交为干净项目，随后每个小功能单独提交。

## 3. 推荐目录

```text
res://
  scenes/
    main.tscn
    world.tscn
    buildings/building.tscn
    ui/hud.tscn
  scripts/
    core/game_state.gd
    core/grid_state.gd
    economy/economy_system.gd
    buildings/building_definition.gd
    buildings/building_system.gd
    buildings/building_view.gd
    input/build_controller.gd
    regions/region_system.gd         # M2
    regions/region_overlay.gd        # M2
  data/
    buildings/                       # BuildingDefinition .tres
  tiles/
    terrain_tileset.tres
  art/placeholder/
```

初期不需要刻意将每个数据模块做成 Autoload；`GameState` 可以在主场景中集中持有依赖。仅当多场景确实需要跨场景持久状态时再使用 Autoload。

## 4. 主场景结构

```text
Main (Node2D)
├── GameState (Node)
│   ├── EconomySystem (Node)
│   ├── BuildingSystem (Node)
│   └── RegionSystem (Node)          # M2
├── World (Node2D; y_sort_enabled 按显示需求设置)
│   ├── Ground (TileMapLayer)
│   ├── Decorations (TileMapLayer)
│   ├── Buildings (Node2D)
│   ├── BuildPreview (Node2D)
│   └── RegionOverlay (Node2D)       # M2
├── Camera2D
└── HUD (CanvasLayer)
    ├── ResourcePanel (Control)
    ├── BuildPalette (Control)
    └── RegionPanel (Control)        # M2
```

`World` 下的地面与建筑必须使用同一坐标参照；对于等距排序，检查 `World/Buildings` 的 Y 排序设置及建筑图片原点是否位于地面接触点。可让建筑节点位置取其**底部锚点**，图片向上延伸。

## 5. 模块数据模型

### 5.1 BuildingDefinition（建筑静态定义）

```gdscript
# res://scripts/buildings/building_definition.gd
class_name BuildingDefinition
extends Resource

@export var building_id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var footprint: Vector2i = Vector2i.ONE
@export var build_cost: Dictionary = {}  # 例：{"wood": 10, "gold": 20}
@export var upkeep_per_tick: Dictionary = {}
@export var output_per_tick: Dictionary = {}
@export var required_workers: int = 0
@export var housing_capacity: int = 0
@export var food_capacity: int = 0
@export var energy_supply: int = 0
@export var energy_demand: int = 0
```

注：这里的字段服务于**原型**，并非《亿万僵尸》原版资源公式。产出、维护和供需在 EconomySystem 中统一处理，避免建筑 Sprite 各自修改库存。

### 5.2 BuildingInstance（运行时状态）

最低字段：`instance_id`、`definition_id`、`origin_cell`、`rotation`（M1 可锁定 0）、`construction_state`。M1 可将建造立即完成；如果随后加入施工时间，再新增 `build_progress`。

### 5.3 GridState（占地）

- `map_width`, `map_height`：固定地图范围。
- `occupied_cells: Dictionary`：键为 `Vector2i`，值为建筑实例 ID。
- `terrain_flags`：标记是否可建造的地形；M1 只需要 `buildable`。
- **建筑占地统一按照左上逻辑格 `origin_cell` 和 `footprint` 计算**，不要依赖图像的长宽。

### 5.4 EconomyState（全局资源）

`resources`（金币、木材、食物等库存）、`workers_total`、`workers_used`、`energy_supply`、`energy_demand`。人口、食物和能源的属性先定义清楚是“库存”“容量”还是“流量”，禁止混用。

M1 简化为：金币/木材为库存；住房提供工人容量；建筑占用工人；发电建筑提供能源容量；食物生产提供人口支持容量。以后再升级为时间相关系统。

## 6. 坐标系统（先完成并测试）

### 概念

- `cell = Vector2i(x, y)`：逻辑网格坐标。
- `local_pos`：`Ground` 图层的本地像素坐标。
- `global_pos`：世界全局坐标。

优先调用 Godot 内置转换接口，**不要自己另写一份等距换算公式**。

```gdscript
@onready var ground: TileMapLayer = $World/Ground

func mouse_to_cell() -> Vector2i:
    var local_mouse: Vector2 = ground.to_local(get_global_mouse_position())
    return ground.local_to_map(local_mouse)

func cell_to_world(cell: Vector2i) -> Vector2:
    return ground.to_global(ground.map_to_local(cell))
```

**关键提醒：** `map_to_local()` 返回的是地块中心，且忽略瓦片贴图的 texture origin；放置有高度的建筑时，必须单独校准建筑根节点的锚点。对于 2×2 建筑，不能直接把原点格中心当成整栋建筑的视觉中心——应根据占地选定逻辑锚点并测试偏移。

## 7. 建筑放置流程

```text
玩家选择建筑类型
    ↓
鼠标位置 → 格子坐标
    ↓
计算 footprint 覆盖的所有格子
    ↓
判定越界 / 不可建设地形 / 占地冲突 / 扩张范围 / 资源是否足够
    ↓
预览绿色（合法）或红色（不合法）
    ↓
左键确认 → 扣除资源 → 建立 BuildingInstance → 占用格子 → 创建 BuildingView
    ↓
更新资源 UI 与建造状态
```

### 单一校验接口

```gdscript
func cells_for_footprint(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
    var cells: Array[Vector2i] = []
    for y in range(size.y):
        for x in range(size.x):
            cells.append(origin + Vector2i(x, y))
    return cells

func can_place(origin: Vector2i, size: Vector2i) -> bool:
    for cell in cells_for_footprint(origin, size):
        if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
            return false
        if occupied_cells.has(cell):
            return false
        if not is_terrain_buildable(cell):
            return false
    return true
```

上面只给出占地/地形检查。正式 `try_place_building()` 必须额外验证：建筑定义存在、可建设范围、资源、工人/能源约束，并且仅在全部成功后扣费和写入占地；失败时不能产生半成品状态。

### 建造、拆除边界

- 右键或 Esc 取消预览。
- 手动拆除时解除所有占地，撤销建筑持续效果；是否退款 M1 可固定为 0。
- 默认不允许建筑互相重叠；道路、围墙等特殊规则以后再做。
- 不在 `BuildingView._process()` 中改资源或改变地图规则。

## 8. 最小经济循环

### 建议资源与建筑

| 类别 | 内容 | 第一阶段作用 |
|---|---|---|
| 初始建筑 | 指挥中心 | 提供初始资源、允许扩张或起始建设范围 |
| 住房 | 住宅 | 增加工人/人口容量并产出金币 |
| 采集 | 伐木场 | 周期产出木材 |
| 食物 | 农场 | 提供食物支持容量 |
| 能源 | 发电设施 | 提供能源容量 |
| 扩张 | 供电/前哨设施 | 扩大允许建设的范围 |

### 周期结算

- 推荐模拟时间独立于帧率，例如每 `1.0` 游戏秒为一经济 tick（仅示例）。
- 每 tick 收集全部已建成建筑的产出与维护费用；统一结算一次并触发资源变化信号。
- 建造/拆除建筑后重新计算工人、食物、能源等容量，避免长期累积漂移。
- 为原型定义统一的缺电、缺工人规则。例如超额时禁止新建筑生效/新建造，暂时不设计复杂的停产优先级。
- 开始时使用简单平衡参数，不追求复刻原版精确数值。

**验证玩法所需的最小经济环：** 住房带来金币与可用工人；伐木场带来木材；建造新设施消耗金币/木材并占用工人；食物与能源限制增长；扩张设施解锁新建造空间。

## 9. M1 分步施工任务

### M1-01 项目骨架

- [ ] 创建 Godot 项目、基础目录、Main/World/HUD 场景。
- [ ] `GameState` 集中管理系统依赖。
- [ ] Git 初始化；能够正常打开和运行空场景。

**验收：** 无报错，能进入主场景。

### M1-02 等距地图与镜头

- [ ] 新建 `TileSet`，Tile Shape 设为 Isometric。
- [ ] 用 `TileMapLayer` 绘制 32×32 的固定地面。
- [ ] 实现 WASD 平移、滚轮缩放和边界限制。
- [ ] 鼠标悬停显示格子坐标和高亮。
- [ ] 校验边缘、角落、快速平移后命中的格子。

**验收：** 鼠标指向任意菱形时，高亮格与逻辑格一致。

### M1-03 建筑放置

- [ ] 创建 1×1 和 2×2 占地的两种占位建筑。
- [ ] 建筑跟随鼠标预览，合法/非法显示不同颜色。
- [ ] 左键放置、Esc 取消、右键拆除（或单独拆除工具）。
- [ ] 实现边界、地形、占地冲突校验。
- [ ] 建筑深度排序/遮挡正确。

**验收：** 2×2 无越界、无重叠、可重复拆建，无残留占地。

### M1-04 资源与基础经济

- [ ] 定义建筑资源，做出指挥中心、住房、伐木场、农场、发电设施、扩张设施。
- [ ] 资源 UI 显示库存、产出变化、容量/占用。
- [ ] 建造前检查成本，建造成功才扣资源。
- [ ] 周期更新金币、木材；重新计算工人、食物、能源容量。
- [ ] 拆除建筑后产出停止，容量正确回退。

**验收：** 玩家能通过发展经济，持续建设；资源不足时无法放置建筑。

### M1-05 建设范围与基础体验

- [ ] 定义指挥中心初始覆盖范围。
- [ ] 扩张建筑增加允许建设的区域。
- [ ] 覆盖范围用半透明地图层显示。
- [ ] 建筑信息面板显示名称、消耗、产出、占地。
- [ ] 可暂停、倍速；所有经济变化与游戏时间一致。

**验收：** 玩家必须通过扩张设施才能在远处建造；暂停时经济不结算。

### M1-06 稳定性回归

- [ ] 连续建造/拆除 100 次，无占地或资源错误。
- [ ] 在地图四边放置大建筑验证越界。
- [ ] 同时存在大量建筑时 UI 统计与库存正确。
- [ ] 切换暂停/倍速，结果稳定且无重复结算。
- [ ] 如有余力再做 JSON 存档；不是 M1 核心门槛。

**验收：** 一局 15～20 分钟的自由建设测试能够稳定进行。

## 10. M2：区块视图（M1 稳定后再做）

### 数据

- 固定逻辑格区块，先每 8×8 格为一区（32×32 地图共 4×4 区块）。
- `get_region_id(cell)` 根据格子坐标计算归属；建筑按**占地锚点**统一归属一个区块，跨区建筑规则暂定为按锚点统计。
- 各区域实时统计：建筑总数、建筑类型数量、占用格数、资源产出（按建筑归属汇总）。

### 表现

- Tab 切换实体视图与区块叠加视图；**不是创建第二个模拟世界**。
- 区块颜色边框、名称/ID、关键信息标签。
- 点击区块右侧显示区域统计。
- 统计更新可以由建造、拆除、资源结算信号触发；先保证正确，再考虑缓存。

### 验收

- [ ] A 视图放置建筑，B 视图立即体现。
- [ ] B 视图选中区块，再切回 A，世界运行状态完全不变。
- [ ] 区块边界与格子坐标对齐，点击判断正确。
- [ ] 仅展示数据，不添加新的经济、施工、占领逻辑。

## 11. 推荐开发顺序（遵守依赖）

`等距坐标 → 网格占地 → 放置/拆除 → 资源扣费 → 经济 tick → 扩张范围 → UI 完整化 → 区块划分 → 区块统计 → 双视图切换`

**不要颠倒先后：** 没有稳固的格子坐标与建筑实例模型，不要开始制作区块逻辑；没有经济闭环，不要开始自动化规划。

## 12. 关键测试清单

| 测试 | 预期 |
|---|---|
| 光标指向地图四角 | 正确转为有效格子或越界状态 |
| 2×2 建筑跨地图边界 | 禁止放置，不扣费 |
| 2×2 和 1×1 占地重叠 | 禁止放置，不扣费 |
| 建筑资源刚好够 | 成功一次，不能重复透支 |
| 连续删除两栋建筑 | 所有格子释放，产出/容量正确调整 |
| 暂停时经过现实 10 秒 | 游戏经济不变化 |
| 多倍速运行 | 结算随游戏时间推进，而不是 UI 帧率 |
| 切换区块视图 | 不创建/销毁实体状态，不改变库存 |
| 跨区建筑 | 按已定义的锚点归属规则统计一次 |

## 13. 后续设计记录（不开发）

- 单基地、全局共享经济。
- 实体世界视图 + 区块管理视图，同一世界状态。
- 保留手动建造、单位指挥；长期希望叠加战略规划与自动化执行。
- 清剿目标区域所有非己方单位及建筑后自动占领，边界条件待未来军事系统确定。
- 大规模单位、动态战线、预备队、自动维修与长期任务均暂缓。

## 14. 开工日的最小任务（强烈推荐）

**只做下面四件事，不做资源系统：**

1. 在 Godot 中创建 `Main.tscn`、`Ground(TileMapLayer)`、`Camera2D`。
2. 使用一张 128×64 的等距地砖绘制 20×20 地图。
3. 显示光标所在逻辑格坐标，给该格加半透明高亮。
4. 将一张占位房屋图片准确放到选定格子，确认锚点与前后遮挡。

成功以后再进行 2×2 占地测试。**首日目标不是“已经有 RTS”，而是把空间坐标体系一次做对。**
