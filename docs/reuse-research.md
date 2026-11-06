# 模块复用：已有方案调研

> 调研日期：2026-11-04～2026-11-06。按当前实现整理。\
> 范围：支撑 architecture.md 的模块复用选型；本稿是来源核对和建议，不表示候选已接入或完成适配/性能验证。\
> 已确认原则：新建项目，旧原型实现不再使用；外部模块能复用就复用，不能复用先找其他已有方案。开发顺序见 development-plan.md。
> 当前直接复用与候选分别标明；检查结果见 [M5 实施记录](../validation/m5-threat-defense.md)，不以调研替代玩法或性能验收。

## 1. 结论

项目采用 2D 等距、模拟/表现分离；已比较 Godot 内置能力、RTS Advanced Lite 的可适配模块与其他已有方案。旧原型代码、场景与内容定义不纳入候选。只有确认外部方案不适合后，才实现本项目特有规则。

## 2. 模块复用入口

这些是检索到的已有候选，不是已经选定的新框架。每个来源均须核对维护情况、许可证与 Godot 4.7 兼容性，不能仅凭 README 或星数决定采用。

| 模块 | 优先复用来源 | 不能复用时的已有候选 | 当前结论与限制 |
|---|---|---|---|
| 2D 等距镜头、地图坐标、建造预览、时钟 | Godot 内置 2D/网格能力与外部可适配模块 | Crusade 的等距镜头/地图实现；其他固定步长/放置方案按功能检索 | M1–M3 已使用原生固定物理步、Camera2D 与项目坐标/预览适配；Crusade 要求 4.4.1，未导入其场景运行时 |
| 选择集合、编队、输入绑定、队列/阵型语义 | RTS Advanced Lite | rluders/rts-framework 的 SelectionManager/CommandManager；Crusade 的选择与单位控制 | 选择/编队/队列已由项目实现；Lite 整框架不采用（§7），独立输入绑定模块保留为 M6 候选（§8） |
| 玩家单位与局部战术 A* | 可脱离场景树的已有寻路实现 | Godot 内置 AStarGrid2D | M2 已接入原生 AStarGrid2D，M3 支持建筑占用变更后的重建与路径更新；正式单位已接入，规模性能待测 |
| 小地图 | 先查已有 2D 小地图方案，Lite 无此模块 | Razoric480/godot-minimap-demo | 新工程需接入或实现；该候选为旧演示项目，Godot 4.7 接入与素材许可仍需核对；不直接导入素材 |
| 机潮流场 | 先查已有 Godot 流场实现 | Crusade 的流场与局部避让实现；Mindustry Pathfinder 成本模型 | M5 行军场为项目自有加权场 `sim/march_field.gd`（软成本口径，§9/§10）；直接复用 Crusade `steering.gd`（分离），`flow_field.gd` 已随设计变更从 vendor 移除；游荡敌走既有 AStarGrid2D |

每项正式采用前记录：源 URL、许可证原文位置、版本/提交 SHA、引擎依赖、需修改的接口、已知问题、适配验证结果。可复用模块锁版本入 vendor；未选候选不导入工程。

## 3. 一手来源

- [RTS Advanced Lite README](https://github.com/openclawaimac/godot-rts-advanced-lite#readme)：3D 基座、Lite/Pro 能力边界、MIT。
- [Crusade README](https://github.com/saman-mb/crusade-rts#readme)：MIT、2D 等距地图/镜头/选择、流场候选与 Godot 4.4.1 要求。
- [Crusade src/core/flow_field.gd](https://github.com/saman-mb/crusade-rts/blob/main/src/core/flow_field.gd)：曾 vendor 的流场核心一手源码；0.5.1 设计变更后已移除（§9），上游本地副本仍在 `d:\fish\crusade-rts\`。
- [RTS Framework README](https://github.com/rluders/rts-framework#readme)：MIT、选择与命令模块及其场景依赖。
- [AStarGrid2D 官方文档](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html)：内置 2D 网格寻路接口。
- [Godot Minimap Demo README](https://github.com/Razoric480/godot-minimap-demo#readme)：MIT 代码仓库与 2D 小地图表示演示；不据此认定演示素材均可沿用。
- [godot-tilemap-flowfields](https://github.com/arnemileswinter/godot-tilemap-flowfields)：MIT、Godot 3.5 GDNative/Rust 流场插件，§9 排除。
- [openage pathfinding](https://github.com/SFTtech/openage)：GPLv3、C++/Python 引擎级扇区/门户 + 流场实现，§9 仅参考。
- [bevy_pathfinder](https://lib.rs/crates/bevy_pathfinder)：MIT、Rust 流场 crate，§9 仅参考。
- [Pathfindax（NuGet）](https://www.nuget.org/packages/Pathfindax)：C# 寻路框架，2019-09 后停更，§9 排除。

调研方式：检查项目与官方源码/README/issue。本环境未找到 Agent-Reach 命令，改用可用的网页检索和一手源码；未执行任何候选运行时，未选候选不导入工程；正式采用者按 §2 锁版本入 vendor（迄今为 vendor/crusade，见 §9）。

## 4. M3 建造与经济选型（2026-11-05）

| 来源 | 许可证 / 接入成本 | 采用结论 |
|---|---|---|
| RTS Advanced Lite | MIT；3D 场景与单位模块，Lite 不提供完整建造系统 | 无可直接接入的建造经济模块，不为 M3 导入整个框架 |
| [Mindustry ConstructBlock](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/world/blocks/ConstructBlock.java) | GPL-3.0；Java、物品供料与世界建筑生命周期依赖 | 借鉴独立建造状态、取消与完工切换的设计；本项目为多资源预付、并行时间施工，不复制源码 |
| [OpenRA RepairableBuilding](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/Buildings/RepairableBuilding.cs) | GPL-3.0；C# Actor/Trait 与玩家经济依赖 | 参考模拟 tick 中小步扣费与修复的成熟做法；不复制源码，不接入其运行时 |
| [Godot Geometry2D](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html) | 随引擎提供 | 直接复用 `bresenham_line` 生成墙线，预览与提交用同一组逻辑格 |
| [Godot ConfirmationDialog](https://docs.godotengine.org/en/stable/classes/class_confirmationdialog.html) | 随引擎提供 | 直接复用拆除确认弹窗；继续复用原生 Camera2D、AStarGrid2D、Resource、Control 与进度条 |

生命周期与维修参考的是上述项目的设计，没有将 GPL 源码引入仓库；未产生需锁版本的第三方代码依赖。建筑参数使用原生 `.tres` Resource；预付预留、容量恢复例外、施工与血量独立是本项目 sim 规则。M3 未验证 M5 机潮性能，也不据此改变后续流场选型。

## 5. 新版经济与采矿（2026-11-05）

比较高星、持续维护的 [Mindustry Drill](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/world/blocks/production/Drill.java)（GPL-3.0，Java / Block / 物品及液体依赖）与 [OpenRA ResourceLayer](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/World/ResourceLayer.cs)（GPL-3.0-or-later，C# / World / Trait / 地图依赖）。参考覆盖矿格校验、独立资源层与储量变化的职责划分；两者均不能直接作为纯数据 GDScript 模块接入，未复制源码或素材。

实际复用 Godot Vector4i 保存币/矿石/金属/稀有的固定分量，Resource 保存建筑与矿点初值，沿用现有固定步长、串行命令和视图。有限矿点、一站一矿、逐资源预付退款及每分钟余数累积由本项目 sim 装配，无新增第三方依赖。Agent-Reach 仍未安装，使用网页检索与一手源码核对。所有实体继续使用几何白模，无新美术依赖。

## 6. M4 生产与单位（2026-11-05）

复核 [RTS Advanced Lite README](https://github.com/openclawaimac/godot-rts-advanced-lite#readme)（MIT，3D 选择/阵型/分离/生产）和高星项目 [OpenRA ProductionQueue](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/Player/ProductionQueue.cs)（GPL-3.0-or-later，C# Actor/Traits、独立队列与预付选项）。Lite 的地面拾取/影子节点仍依赖 3D 适配，OpenRA 依赖其世界与规则运行时，均不直接导入。

选择继续复用原生 Rect2/Geometry2D、AStarGrid2D 与现有串行命令；新增纯数据生产队列、单位状态和客户端选择集合。移动直接复用原生 A* 与下述 RVO，友军临时占位不封路或替换指令终点；生产扩展本项目已有账本及预留事务。未复制第三方源码，未产生新 vendor 或许可证依赖；未将 4 单位训练场视为最终规模性能验证。

### 窄口拥堵：直接采用原生 RVO（2026-11-06）

用户反馈主脑与组装厂之间易卡住。初版把友军当硬碰撞，堵塞后再封掉友军整格。此前修补仅参考设计、自写侧让和软分离，未达到直接使用成熟方案的要求，现已删除。

| 比较来源 | 实现与依赖 | 本轮决定 |
|---|---|---|
| 高星、持续维护的 [Godot NavigationServer2D](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html) | 引擎自带 RVO2；RID、物理帧速度回调与静态障碍接口；不要求单位成为场景节点 | **直接调用原生求解器**；继续直接使用原生 AStarGrid2D，不额外移植避让算法 |
| 高星、持续维护的 [OpenRA Move](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Activities/Move/Move.cs) | GPL-3.0，依赖 C# Actor/Locomotor 运行时 | 不导入；其等待/让路设计不能算作本项目已直接复用实现 |

已核对 Godot 4.7 分支的 [NavAgent2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/navigation_2d/nav_agent_2d.cpp) 与 [NavMap2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/navigation_2d/nav_map_2d.cpp) 一手源码。实际运行依赖为本机 Godot 4.7.2 `ed1daf0bf`，引擎 MIT，内置 RVO2 为 Apache-2.0，见 [版权清单](https://github.com/godotengine/godot/blob/4.7-stable/COPYRIGHT.txt)。没有复制或修改求解器源码，也没有新增 vendor。

`sim/crowd_navigation.gd` 是 API 适配层：提交逻辑坐标/期望速度，注册单位与建筑/地形障碍，收齐原生回调后批量落地。暂停停用专属地图；命令使旧批次失效；重开/退出释放 RID；仅瞬移时清零原生速度状态。指令、A* 路点跟随、地形减速和最终静态碰撞校验仍由项目负责，避让方向与速度由原生 RVO 求解，没有自写侧让/推挤回退。

后续目标漂移反馈修正的是项目指令适配：友军临时占位不再替换点击格/阵型终点；最后路点在原生位移实际提交后确认，空路径重试原目标。单兵静态不可达时拒绝下令，不寻找附近替代终点。求路与避让仍分别直接调用原生 AStarGrid2D 与 RVO，没有新增避让或寻路算法。

按 [官方回调时序](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationservers.html)，提交发生在固定物理帧，移动提交和视图刷新在同帧的原生回调收齐后执行，不在每个单独回调中各自刷新。已知限制：RVO 不能保证所有拥堵场景都能解开，[官方说明](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html) 提示完全对称的迎面情形可能失败。当前 36 个脚本语法与双场景启动已通过，窄口通行/编队已有用户人工复验；暂停、资源生命周期与其余交互仍待补验，范围见 [M5 检查记录](../validation/m5-threat-defense.md)。

## 7. RTS Advanced Lite 整框架采用结论

当前不采用 Lite 整框架。其单位、选择投影和地面拾取依赖 3D 场景节点，直接接入与本项目 2D 等距、无头 sim 边界冲突；Lite 缺少建造、多资源经济、电力覆盖、容量、采矿与波次系统。项目已有原生 AStarGrid2D/RVO 路线，Lite 的自写分离不能替代现行原生求解器。

后续未实现的键位绑定等模块继续逐项评估；不因整框架未采用而跳过可独立复用模块，候选详见 §8。

## 8. Lite 源码通读核查（2026-11-06，本地参考副本）

用户下载了 Lite 源码副本（main 分支 zip，HEAD `81e757ba`；版本 0.3.0，2026-10-15；MIT 见仓库 LICENSE 首行 SPDX 标识）。逐文件通读 14 个 addon 模块、demo 接线与测试模式，与本项目现有实现逐项对照，结论如下。

**值得参考（按里程碑）**：

- **M6 键位重绑定（§2 既定候选的首个一手核查）**：`rts_bindings.gd` 为纯 RefCounted + InputMap 操作，无 3D/场景依赖，可直接适配；提供注册默认动作、`conflict()` 冲突检测、`rebind()` 拒绝占用键、ConfigFile 存/读、`label()` 人类可读键名。本项目现状为 presentation/main.gd `_handle_key` 硬编码 KEY_* 分支与 map_camera.gd 直查物理键。适配点：动作集换成本项目热键（含 R 建造槽与重开键的既有冲突，开发计划 M6 待处理）；其"一动作一物理键"模型需确认与 Ctrl+数字编队等修饰键语义不冲突。
- **M6 选择框实时计数（UX 参考）**：`RTSSelectionBox` 拖拽时经注入的 `count_provider`（每帧至多一次）在光标旁显示"N units"——本项目 HUD 拖框可参考；本项目已有点击/拖动区分、shift/ctrl、编队与失效剔除（selection_state.gd），无缺口。
- **收敛印证**：`rts_grid_nav.gd` 同样直接用原生 AStarGrid2D + DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES + OCTILE 启发式，且同样"首路点若可视直达则跳过"——与 grid_navigation.gd 两处做法一致，属独立收敛，不作改动。
- **生产队列可选 QoL（设计未要求，不主动加）**：`rts_production.gd` 的 repeat（完工自动续订、可负担才续）、produced_tagged 标签、speed 乘数。若日后设计稿提出"连续生产"或"生产加速"，可参考其实现；本项目预付/占容/退款/受阻语义更完整，保持不动。
- **测试 harness 模式**：`tests/harness.gd` 以 Logger 挂钩统计 SCRIPT ERROR、按 expected.json 严对账段数/检查数。本项目 AGENT.md 不写测试脚本，此模式仅供用户开发环境自行参考，不入库。

**已核实的分歧（本项目保持不动）**：`nearest_open` 螺旋把目标吸附到最近可走格——本项目规则为"单兵静态不可达拒绝下令，不找替代终点"；`rts_separation.gd` O(n²) 自写分离——已被原生 RVO 替代（§6）；`rts_unit.gd` 为 Node3D 场景节点、战斗仅单位对单位——违反无头 sim 红线，且 M5 所需的建筑目标、流场行军、波次 Lite 均不提供；formation/orders 的贪心槽位分配——本项目已按"成组落点一次分配 + 保留原目的地"规则实现。camera（3D）、economy/resource_node（单币/可占领点模型）、loc（无 i18n 需求）、teams（关系表；本项目仅玩家/机潮两方，team 字段已够）均不适用。

**副本位置**：副本已按用户指示移出项目目录，现位于 `d:\fish\godot-rts-advanced-lite-main\`（与其他参考仓库同级，不参与本项目 Godot 扫描与导入）。

## 9. M5 行军场与分离选型

当前机潮采用加权软成本场：地形权重 × 建筑软成本，目标为主脑；占用变化重算、HP 漂移限频刷新。接敌后走既有 AStarGrid2D，接敌判定与分离走网格桶，游荡敌按噪声各自寻路。

| 候选 | 许可证与依赖 | 当前结论 |
|---|---|---|
| [Crusade RTS](https://github.com/saman-mb/crusade-rts) flow_field / steering | MIT；Godot 4.4、纯 RefCounted；锁定 `e4929c8` | 直接 vendor `steering.gd`；均匀成本 BFS 无法表达建筑软成本择路，flow_field 已移出工程 |
| [godot-tilemap-flowfields](https://github.com/arnemileswinter/godot-tilemap-flowfields) | MIT；Godot 3.5 GDNative/Rust、FlowFieldGenerator/TileMap | 引擎版本、原生二进制和节点耦合不满足当前边界 |
| [openage pathfinding](https://github.com/SFTtech/openage) | GPLv3；C++/Python、扇区/门户与流场 | 仅参考分层/缓存设计，不复制源码或接入运行时 |
| [bevy_pathfinder](https://lib.rs/crates/bevy_pathfinder) | MIT；Rust crate | 需要新增原生扩展工具链；仅作候选参考 |
| [Pathfindax](https://www.nuget.org/packages/Pathfindax) | C#、Duality、.NET Framework 4.7.2；调研记录最后更新 2019-09 | 依赖与版本不适合直接接入，不为其引入 .NET 工具链 |

Godot 当前项目使用的 NavigationServer2D 与 AStarGrid2D 提供逐 agent 能力，不提供所需的共享加权积分场。已核对候选中没有可直接接入且符合当前边界的加权场，因此 `sim/march_field.gd` 为项目自写 Dijkstra/二叉堆实现；成本模型参考 Mindustry（§10），不复制其源码，不算直接复用。

**实际 vendor**：`vendor/crusade/steering.gd` 逐字复用，MIT 全文随附，锁定 `e4929c8`。分离半径由调用方注入，项目负责邻居查询、状态切换与位移守卫。`flow_follower.gd` 耦合上游等距/高程几何，其贴墙滑动语义也与撞墙接敌冲突，因此不导入。采用文件与限制见 [vendor 说明](../vendor/crusade/README.md)。

源码分析时的本地参考副本位于 `d:/fish/crusade-rts/` 与 `d:/fish/godot-tilemap-flowfields/`，不作为工程运行依赖。原生寻路、RVO 与 vendor 之外的业务接线由项目负责；语法检查通过不表示封墙、缺口分流或目标规模已通过实机验收。

## 10. 巨量单位 RTS 架构对照

以下保留规模治理、波次与寻路的设计对照；未引入这些项目的代码或运行时，表中规模属于参考项目，不是本项目实测结果：

| 参考 | 规模与形态 | 对本项目的印证与差异 |
|---|---|---|
| [RecoilEngine](https://github.com/beyond-all-reason/RecoilEngine)（Spring 后继，BAR 引擎） | 设计目标 ~1 万并发单位、实测 ~1.77 万；C++23，固定 30Hz 确定性模拟层 + `for_mt` 多线程 + 四叉树寻路（HAPFS/QTPFS）+ 渲染帧间插值 | 30Hz 固定步长确定性模拟与本作一致；但其规模靠多线程并行，GDScript 无此路线，本作规模治理仍按架构稿 §9（分区休眠/迷雾外降档/降速阀）。BAR PvE 层（Scavengers/Raptors gadgets）给出波次系统成熟形态：grace period 静默（120–360s 按难度）、anger 进度（时间+玩家经济驱动）、数据驱动波次表（`configs/scav_spawn_defs.lua`）、波内 squad 编组与冷却 |
| [Mindustry](https://github.com/Anuken/Mindustry)（GPL-3.0，Java） | 数千单位，单线程主循环 | **与本作同构**：波次方共享"向核心的流场"（`Pathfinder.preloadPath(getField(waveTeam, costGround, fieldCore))`），`SpawnGroup` 数据驱动波次构成（begin/spacing/unitScaling/max）。其"建筑血量折成软成本烘进流场、敌人择最薄墙突入"的方案**经用户决策采用**（§9）：行军场改为加权软成本（`sim/march_field.gd`），缺口足够便宜时敌人自动弃墙走缺口；差异仅剩本作用"占用即时 + HP 限频 1s 重算"替代其增量更新 |
| [openage](https://github.com/SFTtech/openage)（GPLv3） | AoE2 引擎重制：扇区/门户分层 + 逐扇区流场 | 分区休眠（架构稿 §9）的蓝图来源；流场缓存/复用思路供后续噪声目标场参考（§9 已记） |
| [OpenRA](https://github.com/OpenRA/OpenRA)（GPL） | 中规模 lockstep RTS，Actor/Trait | 命令即意图、tick 串行执行——与本项目命令队列同构（§4/§6 已记） |
| Supreme Commander（闭源） | 500 单位/边设计上限、战略缩放 | 仅设计标尺：证明 1–2k 是"可玩规模"常规区间；无实现可引 |

采用结论：沿用无头固定步长模拟、命令队列、波次流场与空间分区；参考项目的原生多线程方案未接入。本项目出兵遵循两个口径：**波内分批出生**（BAR squad/冷却思路的简化版，避免单 tick 批量插入的峰值）；**波次配置数据驱动**（对标 SpawnGroup/波次表，本作即数值稿 §12 预算曲线，不写死在代码）。
