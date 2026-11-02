# Billions Mech｜区域指挥型生存 RTS

以《亿万僵尸》式基地经济为起点、后续叠加区块指挥视图的 2D 等距 RTS 原型。

- 设计文档：[区域指挥型生存RTS_设计文档_v0.2.md](区域指挥型生存RTS_设计文档_v0.2.md)
- 开发指南：[区域指挥生存RTS_基础开发指南_v0.1.md](区域指挥生存RTS_基础开发指南_v0.1.md)
- 当前阶段：**M1-01 项目骨架已完成**，下一步 M1-02 等距地图与镜头。

## 环境

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7.2 stable（Steam 版，`godot` 命令已在 PATH） |
| 语言 | GDScript |
| 渲染 | GL Compatibility |
| 视口 | 1600 × 900，`canvas_items` 缩放 |
| 地图 | 32 × 32 逻辑格（`GameState` 可调） |

运行方式：用 Godot 打开本目录的 `project.godot`，按 F5；或命令行：

```powershell
godot --path .                      # 运行主场景
godot --headless --path . --import  # 只导入资源
```

## 目录结构

```text
res://
  project.godot
  icon.svg
  scenes/
    main.tscn                 # 入口：GameState + World + Camera2D + HUD
    world.tscn                # 视图层：Ground/Decorations/Buildings/BuildPreview/RegionOverlay
    ui/hud.tscn               # 资源栏、建造菜单占位、区块面板占位
    buildings/                # 建筑视图场景（M1-03）
  scripts/
    main.gd                   # 装配与全局输入
    core/
      game_state.gd           # 唯一世界状态持有者 / 系统装配
      grid_state.gd           # 二维逻辑网格、占地、地形阻挡
      simulation_clock.gd     # 固定步长模拟时钟（暂停/倍速）
    economy/economy_system.gd # 库存资源 + 容量约束 + 周期结算
    buildings/
      building_definition.gd  # 建筑静态定义（.tres）
      building_instance.gd    # 建筑运行时实例（纯数据）
      building_system.gd      # 建造/拆除唯一入口
    regions/region_system.gd  # 区块划分（M2 数据层，暂不统计）
    ui/
      hud.gd                  # 只读 GameState，通过信号刷新
      resource_panel.gd       # 顶部资源栏
    world/world.gd            # 逻辑格 <-> 世界坐标转换
    input/                    # 建造/镜头输入控制（M1-02、M1-03）
  data/buildings/             # BuildingDefinition .tres（M1-04 填充）
  tiles/                      # TileSet（M1-02）
  art/placeholder/            # 占位美术
  ui/fonts/                   # 中文系统字体（SystemFont，不打包字体文件）
  临时素材/                    # 用户提供的 AI 生成素材原图（1254×1254，待裁切）
```

## 架构约定

```text
GameState（唯一真实状态，主场景内持有）
├── SimulationClock   固定 tick，驱动经济结算
├── GridState         逻辑格、占地、地形阻挡
├── EconomySystem     库存（金币/木材）+ 容量（工人/食物/能源）
├── BuildingSystem    建筑定义、实例、建造/拆除
└── RegionSystem      区块划分（M2）

视图层：World / HUD
  只读 GameState，只接收信号，不修改模拟数据
```

必须遵守的几条：

1. **二维逻辑网格是唯一空间真相。** 建筑占地只看 `origin_cell + footprint`，不看贴图尺寸。
2. **数据先于表现。** 建造/拆除先改 `GridState` 与 `instances`，再发信号让视图创建/销毁节点；视图不得先行动画。
3. **统一命令入口。** 手动建造与未来的规划层都调用 `BuildingSystem.try_place_building()` / `remove_building()`；UI 不自行判断合法性、不直接改资源。
4. **经济按模拟时间结算。** 收益只在 `SimulationClock.tick` 里由 `EconomySystem.process_tick()` 计算，禁止在 `_process(delta)` 里按帧累加。
5. **容量与库存分开。** 金币/木材是库存；工人/食物/能源是“供给 vs 占用”的容量约束。
6. **区块不产生经济。** `RegionSystem` 只做格到区的映射与聚合，M2 的统计必须从建筑实例读取。

数据流：

```text
玩家输入 → BuildingSystem（校验 → 扣费 → 占格 → 实例）
        → 信号 buildings_changed / resources_changed / capacity_changed
        → HUD 刷新显示（World 创建/销毁 BuildingView）
        → SimulationClock.tick → EconomySystem.process_tick → resources_changed
```

## 输入映射

| 动作 | 默认按键 | 用途 |
|---|---|---|
| `camera_left/right/up/down` | A/D/W/S 或方向键 | 镜头平移（M1-02 接入） |
| `camera_zoom_in/out` | 鼠标滚轮上/下 | 镜头缩放（M1-02 接入） |
| `cancel_action` | Esc / 鼠标右键 | 取消建造预览（M1-03 接入） |
| `toggle_region_view` | Tab | 切换区块视图（M2 接入） |
| `pause_game` | Space | 暂停/继续（已接入） |

## 新增建筑定义

在 `data/buildings/` 下新建 `.tres`，类型选 `BuildingDefinition`，必填 `building_id`、`display_name`、`footprint`，其余按需：

- `build_cost` / `upkeep_per_tick` / `output_per_tick`：例 `{"gold": 20, "wood": 10}`
- `housing_capacity` / `required_workers`：工人容量与占用
- `food_capacity` / `food_demand`：食物供给与需求
- `energy_supply` / `energy_demand`：能源供给与需求
- `build_range_radius`：扩张设施的建设范围（M1-05）

`BuildingSystem` 启动时会自动扫描该目录，按 `building_id` 注册。

## 已完成 / 下一步

M1-01（已完成）：

- [x] Godot 项目、目录结构、主场景可运行
- [x] `GameState` 集中装配时钟/网格/经济/建筑/区块
- [x] `Main` / `World` / `HUD` 场景与信号绑定
- [x] 输入映射、暂停与游戏时间显示
- [x] Git 初始化

M1-02（下一步）：

- [ ] 等距 `TileSet` 与 32×32 `Ground`
- [ ] WASD 平移、滚轮缩放、相机边界
- [ ] 鼠标悬停格子高亮与坐标显示
- [ ] 用 `临时素材/地块.png` 裁切出 128×64 等距地砖

## 约定

- 脚本文件用 **Tab** 缩进（见 `.editorconfig`），类名与文件名保持一致。
- 节点/资源 ID 用 `StringName`；资源数量用 `String` 键（`"gold"`、`"wood"`）。
- 不写测试脚本；每次改动用 `godot --headless --path . --quit-after 120` 验证无报错。
