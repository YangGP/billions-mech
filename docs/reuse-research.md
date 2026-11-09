# 模块复用：已有方案调研

> 按版本保留的技术决策与来源，后文旧脚本数/旧场景验收仅属当时环境；当前状态见[开发计划](development-plan.md)，最近证据见[验证索引](../validation/README.md)。

> 调研日期：2026-11-04～2026-11-06。按当前实现整理。\
> 范围：支撑 architecture.md 的模块复用选型；本稿是来源核对和建议，不表示候选已接入或完成适配/性能验证。\
> 已确认原则：新建项目，旧原型实现不再使用；外部模块能复用就复用，不能复用先找其他已有方案。开发顺序见 development-plan.md。
> 当前直接复用与候选分别标明；检查结果见 [验证索引](../validation/README.md)，不以调研替代玩法或性能验收。

## 1. 结论

2026-11-08 本轮账本迁移选型：检查[Expresso Inventory](https://github.com/expressobits/inventory-system)（MIT，物品/堆叠与Node/GDExtension库存）及[RTS Framework](https://github.com/rluders/rts-framework)（MIT，完整RTS节点框架）。前者的数据语义是物品实例和库存约束，不是本作无槽位、无上限的全局整数余额；后者需要接管既有场景/命令架构。本轮不借用它们的源码或算法，也不按其思路重写库存系统。直接复用Godot内置[Dictionary](https://docs.godotengine.org/en/stable/classes/class_dictionary.html)的存储、复制与Resource序列化，以及项目已有命令/余数结算；项目仅适配五种资源的业务校验、费用与退款，不引入自制容器、数据库或通用库存框架。

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

按 [官方回调时序](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationservers.html)，提交发生在固定物理帧，移动提交和视图刷新在同帧的原生回调收齐后执行，不在每个单独回调中各自刷新。已知限制：RVO 不能保证所有拥堵场景都能解开，[官方说明](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html) 提示完全对称的迎面情形可能失败。当前 36 个脚本语法与双场景启动已通过，窄口通行/编队已有用户人工复验；暂停、资源生命周期与其余交互仍待补验，范围见 [历史性能专题](../validation/performance-wanderers.md)。

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

当前机潮采用**地形-only** 加权场：只按地形权重积分到主脑，建筑与 HP 不参与全局路线；墙/建筑由局部碰撞接敌处理，场在单局内静态。接敌后走既有 AStarGrid2D，接敌判定与分离走网格桶，游荡敌按噪声各自寻路。

| 候选 | 许可证与依赖 | 当前结论 |
|---|---|---|
| [Crusade RTS](https://github.com/saman-mb/crusade-rts) flow_field / steering | MIT；Godot 4.4、纯 RefCounted；锁定 `e4929c8` | 直接 vendor `steering.gd`；均匀成本 BFS 无法表达本项目的地形权重，flow_field 已移出工程 |
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

## 11. M5 主脑失败与读模型更新

实施前已下载并通读 OpenRA 的 [ConquestVictoryConditions](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/Player/ConquestVictoryConditions.cs)、依赖的 MissionObjectives 与 COPYING，副本现统一位于忽略的 `reference/openra/`。前者 SHA256 为 `399b64e55e7a9fc63ee593756eb2d8958cc88de0e89ae41a262a4a96d9a9d0ec`。模块按玩家必需资产和任务目标判定结果，依赖 C# Actor/Trait、World、Player、任务系统与通知服务，许可为 GPL-3.0-or-later；不能直接接入本项目纯数据 GDScript 会话。本轮仅核对终局状态与通知边界，不复制或移植其源码。

引擎 [SceneTree.paused](https://docs.godotengine.org/en/stable/classes/class_scenetree.html#class-scenetree-property-paused) 会影响节点处理与物理推进，不能直接表达本作“模拟停止、镜头/查看/重开继续”的会话规则。直接复用已有 MechSimulationClock 暂停、MechEntityRegistry.suspend_motion 及其原生 NavigationServer2D 地图停用能力，SimCore 只新增主脑死亡锁定结果、终局命令校验与快照字段；这属于项目业务接线，不新增调度或避让算法。

读模型直接复用 Godot 原生 `_process` 渲染帧回调：状态信号只标脏，帧内输入读取最近发布的同一份快照，下一帧统一发布新状态。命令仍走实时权威校验；暂停/场景切换读取廉价会话查询，不为它们再次打包全量状态。无需引入带场景节点依赖的外部状态管理框架。

## 12. 等距正方形地图与基地禁刷区

已比较 [Clipper2](https://github.com/AngusJohnson/Clipper2)（Boost Software License 1.0，C++/C#/Delphi 多边形布尔运算）与 [Godot Geometry2D](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html)。单独接入 Clipper2 需要新增原生或 .NET 适配，而引擎已提供本次所需接口，因此直接调用原生 `is_point_in_polygon`、`intersect_polygons`、`get_closest_point_to_segment`、`triangulate_polygon`；不自写多边形判断或裁剪算法、不新增 vendor。

保留既有等距投影，以地图 Resource 中的逻辑多边形定义可玩边界，投影后外轮廓为正方形。网格缓存范围掩码，玩家 A*、敌方加权场、放置/拾取与边缘出生共同读取；表现使用原生多边形裁剪。基地禁刷按主脑占地矩形的原生 `Rect2` 钳制距离过滤初始散布与回填候选，是项目玩法规则；后续正常行走、波次和感疫沿用原有规则。

## 13. 扩图后的持续渲染性能

使用原生 [Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html) 监视器和 Time 计时定位：扩大后的地图全景约 28,341 次绘制调用/帧，本机 Compatibility/RTX 4080 SUPER 下稳定约 18–19 FPS；模拟每步约 0.7–0.8ms、界面脚本每帧约 0.54ms。CanvasItem 缓存绘制指令并不等于缓存渲染结果，千余地格/岩体仍持续提交绘制。

先核对 [Godot 官方演示仓库](https://github.com/godotengine/godot-demo-projects)（MIT，viewport 示例）与引擎内置方案。TileMapLayer 原生分块适合已有图集的瓦片地图，本项目当前由多边形与文字绘制白模。此次直接复用 [SubViewport.UPDATE_ONCE](https://docs.godotengine.org/en/stable/classes/class_subviewport.html) + ViewportTexture + Sprite2D，把既有静态画面绘制一次后作为纹理显示；不复制外部源码、不自写渲染缓存算法。静态地图只在新会话/地图加载时更新，建造与移动不会触发重绘；动态实体与覆盖预览继续独立绘制。

保留可选 `--perf` 日志，汇总真实帧率、绘制调用、模拟/表现脚本及原生导航耗时，用于后续定位。它不改变游戏数值或推进频率，不新增测试脚本。

相同 1920×1080 标准开局全景、关闭垂直同步对照：缓存后绘制调用降至 272 次/帧，稳定约 440–470 FPS；默认镜头约 449–456 FPS。该结果只覆盖本机开局持续渲染，不等同于目标千级机潮或鼠标交互验收。

## 14. 基础设置页面

先检索 [Maaack/Godot-Menus-Template](https://github.com/Maaack/Godot-Menus-Template)（MIT，持续维护的菜单模板）。其配套插件覆盖完整菜单与场景加载体系；本项目已有独立模拟暂停命令、HUD 和镜头，整套接入会引入重复的应用生命周期管理。此次直接复用引擎内置 Control/Container、[DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html)、[Engine.max_fps](https://docs.godotengine.org/en/stable/classes/class_engine.html) 和 [ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html)，不复制或仿写模板代码、不新增依赖。

项目代码仅负责设置字段校验、控件与原生 API 绑定、ConfigFile 读写，以及设置页与既有暂停/输入命令的衔接。首版提供窗口/全屏、垂直同步、帧率上限、镜头移动/缩放倍率与边缘滚屏；应用后保存，取消丢弃草稿，默认值须应用才生效。界面使用独立可编辑场景。

## 15. 建筑占地分级

核对 [Godot 官方等距演示](https://github.com/godotengine/godot-demo-projects/tree/master/2d/isometric)（MIT）和当前项目 Resource/footprint 链路：四档建筑大小属于内容配置，已有放置、占用、覆盖、A*、出厂与轮廓直接读取 footprint，无需新增瓦片/建筑模块。主脑改为 4×4；既有白模通过原生 [CanvasItem.draw_set_transform](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html) 按占地缩放，点击轮廓同步缩放，继续复用 Geometry2D 判断。仅调整内容数据、表现适配和训练场点位，不新增算法或依赖；发电厂/中继只确定设计规格。

## 16. 可直达路点引导（2026-11-07）

Agent-Reach 在当前环境未提供，改用网页检索与公开源码核查。先检索 [Godot 官方演示](https://github.com/godotengine/godot-demo-projects)（约 9.8k 星，MIT，持续维护）、[Recast/Detour](https://github.com/recastnavigation/recastnavigation)（约 8.2k 星，zlib）与 [PathFinding.js](https://github.com/qiao/PathFinding.js)（约 8.7k 星，MIT）。官方导航网格演示使用原生漏斗路径，但整体替换会引入导航网格重烘焙/同步，并需另行表达当前逐格崎岖地权重；Recast 为 C++ 导航网格工具链，非当前 GDScript 2D 运行接口。PathFinding.js 的 `smoothenPath` 以可通行射线跳过格点，但为 JavaScript 运行接口，未表达本项目圆形单位宽度和地形时间成本，不能直接接入当前 GDScript 模拟。需由现有网格守卫提供本项目的可达路点选择，不能原样调用上述点单位网格判断。

已下载 Godot **4.7.2-stable** 的 `godot_navigation_server_2d.cpp`、`curve.cpp` 及 PathFinding.js 的 `src/core/Util.js`/README，现统一放在本机 `reference/navigation/`，核对许可证、接口、依赖与关键实现。Godot 的 `simplify_path` 调用原生 NavMeshQueries2D 返回原路径索引，但自身不检测地图障碍；本次只用零容差删除共线点，保留原生 A* 的通路形状。Curve2D 与整个导航网格迁移均不用于最终实现。

实际复用原生 AStarGrid2D、[NavigationServer2D.simplify_path](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html#class-navigationserver2d-method-simplify-path) 与既有 RVO。自写适配是带单位宽度和地形时间成本守卫的路点选择：从当前锚点向路径末尾检查最远可直达点，整段能直达就只保留终点，受阻时才保留绕障拐点。碰撞检查复用 `mobile_segment_clear`，不会只检测中心射线；崎岖地的时间成本不能因捷径变差。移动命令保留点击位置，重寻路不重新吸附格心；成组落点仍保持独立分配。没有实现新的 A*、RDP、曲线求值或局部避让器，也没有把外部参考描述为已接入模块。机潮主脑流场保留原实现；玩家移动、出厂、噪声游荡和接敌追踪共用改后的 A* 路径。未新增测试脚本，执行原生检查与已有回归；交互检查受 computer-use 连接不可用限制。

## 17. 按行进方向安排抵达队列（2026-11-07，实施前核查）

按用户确认的规则，移动方向决定抵达队形的前后/左右，单位就近占据对应落点；掉头时原后排可成为新前排；短距离改点保持相对位置，途中落点稳定，窄口允许散开通过。抵达朝向与实际行走/攻击朝向分别保存。

Agent-Reach 不可用，使用网页检索。先核对高星候选 [Mindustry](https://github.com/Anuken/Mindustry)（约 29.7k 星，GPL-3.0，Java/Arc）、[gdx-ai](https://github.com/libgdx/gdx-ai)（约 1.3k 星，Apache-2.0，Java/libGDX 的 Formation/SlotAssignment 接口）及 Godot 原生导航。前两者不能直接在 GDScript 模拟运行，原生 A*/RVO 不负责队形落点分配。继续核对项目已评估的 [RTS Advanced Lite](https://github.com/openclawaimac/godot-rts-advanced-lite)（MIT，小型项目，不称为高星成熟框架）。

已下载 Lite `rts_formation.gd`、README、LICENSE 和 gdx-ai `FreeSlotAssignmentStrategy.java`，现统一放在本机 `reference/formations/`，逐项核对。Lite 的整个框架是 3D，但 **RTSFormation 本身仅依赖 RefCounted、Array、Vector2/Vector3 与内置数学，无 Node3D/场景依赖**：`box` 生成垂直于行进方向的居中行列，`assign` 按距离贪心分配独立槽位。因此直接保留原文件及 MIT 许可于 `vendor/rts_advanced_lite/`，由适配层将逻辑 Vector2 映射到 XZ 平面后调用，不重写槽位生成/分配算法。此采用范围细化了 §7/§8 的整框架不采用结论。

项目适配负责：以部队中心和目标/路线末段确定朝向，把相对位置平移到目的区域后交给原分配函数以减少远距离命令的前后抢位；短距离或相近方向的新命令优先沿用旧偏移；落点按圆形单位宽度、相互间距和原生 A* 可达性修正，整队校验后一次提交。朝向、稳定落点与显示标记属于本项目业务状态。原生 RVO 保持独立避让，不让单位先原地排齐，也不逐帧重排。贪心分配不宣称全局最短或绝对无交叉。未新增测试脚本；导入/语法、现有回归及画面检查与人工交互验收分别记录。

## 18. 普通移动抵达后的原地开火（2026-11-07）

按用户规则调整已有战斗行为：普通移动途中优先赶路，到达后转待命，只对实际射程内、玩家可见且地形视线畅通的目标开火；敌人离开射程/视线立即放弃，不生成追击路径。A 移执行期间保留较大的索敌半径与追击，指定攻击继续按显式命令追击；两者结束进入待命后采用同一原地开火规则。

先核对持续维护的 [OpenRA AutoTarget](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/AutoTarget.cs) 的扫描半径、`allowMove` 与武器射程区分，源码下载到 `reference/openra/AutoTarget.cs` 并检查既有 COPYING。该模块依赖 C# Actor/Trait、AttackBase 和活动系统，GPL-3.0-or-later，不能直接作为本项目 GDScript 战斗模块接入，未复制或移植。项目已有空间桶、射程/LOS、目标保持、攻击冷却和 A*，只在这些既有接口处限定待命状态的候选范围、缓存目标有效性与追击许可，不新增搜索/战斗算法，也不引入姿态按钮。Agent-Reach 不可用，使用网页和本地源码核对。

## 19. 小地图选型（2026-11-07，实施前核查）

按 §2 既定候选核对 [Razoric480/godot-minimap-demo](https://github.com/Razoric480/godot-minimap-demo)（MIT，2020，演示项目）。已 `git clone --depth 1` 到本地 `reference/godot-minimap-demo/` 并逐文件通读 `project/src/Minimap/`（MinimapManager/Proxy/SpriteProxy/CameraProxy）、README 与 LICENSE。

| 候选 | 实现与依赖 | 采用结论 |
|---|---|---|
| Razoric480/godot-minimap-demo | Godot 3 API（`Sprite`、`camera.current`、Light2D 圆形遮罩）；**每实体一个 Proxy Node**（`_process` 内 `global_position = mirror_master.global_position`）克隆进独立 Viewport 子世界，相机亦克隆 | 不 vendor、不复制源码 |
| 引擎内置能力 | `Control._draw`、`Image.create_from_data`/`ImageTexture`、`draw_polygon(polygon, colors, uvs, texture)`、Camera2D 视口矩形数学 | **直接复用**；与项目既有 `fog_view.gd` 贴图模式同构 |

不兼容原因：代理克隆要求每个实体（含敌人）持有常驻场景节点并逐帧同步位置，与本项目无头 sim、快照读模型（实体仅是 `snapshot()` 字典、非节点）及千级机潮性能目标冲突；其独立 Viewport 子世界会把世界重渲染一遍，抵消静态地形 UPDATE_ONCE 缓存的收益；圆形 Light2D 遮罩与 Unity 风格素材亦非本项目形态。演示素材来自 Unity CodeMonkey 教程，本来也不导入。

实际实现：复用项目既有 `fog_view.gd` 读模型贴图模式——地形（playable/terrain 三色）与三态迷雾各一张逻辑格 `ImageTexture`，经投影轮廓多边形 + UV 贴到小地图 `Control._draw`；实体/矿点/主脑图标/镜头视野框按快照数据以点阵绘制。项目自写部分仅为坐标拟合（letterbox 居中、控件本地↔投影世界互逆换算）与全屏切换布局，不新增算法或 vendor 依赖；将来区域范围叠加层预留绘制位。检查记录见 [小地图检查](../validation/minimap.md)。

## 20. 基座与维修规则（2026-11-07）

纯 sim 规则变更：维修暂停（被攻击后交战状态判定，周边无敌军即恢复）、被毁留基座、重建/清除、一键修复。先核对 [Mindustry](https://github.com/Anuken/Mindustry)（GPL-3.0，Java）与 [OpenRA](https://github.com/OpenRA/OpenRA)（GPL）的废墟/重建处理：两者均把废墟作为引擎内地图实体或 Actor 特性，绑定其各自世界/规则运行时，不能作为本项目无头纯数据 GDScript 模块接入，未复制源码；仅确认"废墟保留占位、付费重建"是成熟 RTS 常见形态。

实际全部复用项目与引擎既有能力：基座复用 `MechBuildingState` 的 Phase 枚举扩展与 CONSTRUCTING 进度/血量爬升机制、`MechResources.scaled` 比例计价、`remove_factory` 队列清理、`_wall_connections` 邻接查询与 ConfirmationDialog 确认框；一键修复复用命令队列与 `building_action_error` 同源校验模式；交战状态复用注册表位置与矩形距离判定。无新增 vendor、无新算法；基座通行豁免（grid 占用保留、寻路放行）是项目自有规则接线。检查记录见 [基座与维修检查](../validation/ruins-repair.md)。

## 21. 卡顿优化与游荡节奏（2026-11-07）

维护现有导航/战斗模块，不更换行军场算法。直接复用 Godot 原生 [WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html)、Mutex、AStarGrid2D 和 NavigationServer2D。按官方[线程安全约束](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)，工作线程只读取独立地图与建筑状态副本，图纸 Resource 在会话内只读；AStarGrid2D 为任务私有实例，任务完成后交接主线程，禁止同一实例并发读写。主线程轮询完成状态，不等待未完成任务；重开/退出才回收仍在运行的任务。只保留一个在途任务，旧地图版本结果丢弃后按最新状态补算。

项目适配仅负责需要判定、版本/脏格记录、输入复制、结果交接和原生 API 调用：玩家 A* 就地更新变更格，RVO 沿用既有按行合并算法但只更新变更行，视野通过原生 PackedByteArray 复制已有探索状态。没有新增线程池、路径求解器、避让算法或 vendor。游荡敌调整复用原有资源字段、状态与移速计算，详见[实施与检查](../validation/performance-wanderers.md)。


## 22. 局部场规则完善（2026-11-08）

本轮维护既有 MechMarchField，不替换或新增积分求解器。沿用现有多源 Dijkstra/堆实现，增加区域内索引、源点标记与边界初值接线；占用判断直接调用既有 MechGridState.is_walkable，追击仍使用 Godot 原生 AStarGrid2D，碰撞与人群分离保持原实现。无需引入外部算法或 vendor。

项目自写部分为用户确认的业务规则：未接敌走可达缺口、已接敌保留目标、建筑只作短距离向前的顺路目标；区域按实际通行类型缓存，使用现有占用脏格失效，复用原生 WorkerThreadPool 计算局部场，限制一个在途任务；输入独立复制，全局场仅只读，结果按局部拓扑校验，重开/退出回收。全局场不包含 HP；局部场使用阻挡状态和可攻击格，不按损血更新。此次为项目现有模块维护，不把本地积分器描述为已接入外部成熟模块。


## 23. 截图视角与 HUD（2026-11-08）

先核对外部 [OpenRA](https://github.com/OpenRA/OpenRA)（GPL-3.0，C#/SDL 游戏引擎）的 RTS HUD 与控件方向：其 UI 绑定引擎自身运行时，不作为本项目 Godot 场景的直接依赖。此次修改既有投影与 Control 布局，没有新写 UI 框架、相机或图像算法，无需移植其实现。

实际直接复用 Godot 原生 [StyleBoxFlat](https://docs.godotengine.org/en/stable/classes/class_styleboxflat.html)、Theme、Control 锚点、[Camera2D](https://docs.godotengine.org/en/stable/classes/class_camera2d.html) 和 [SubViewportContainer](https://docs.godotengine.org/en/stable/classes/class_subviewportcontainer.html)，对象预览复用现有 MechFoundationView。SubViewportContainer.stretch 会让子 Viewport 跟随控件大小，因此预览模型按实际控件尺寸定位缩放。项目自写部分只包括截图推估出的投影参数、HUD 排布/文字、原读模型接线及可视区域计算；保留现有白模风格，无新增 vendor 和外部素材。


## 24. 探图与实时视野分离（2026-11-08）

先检索核对 [OpenRA](https://github.com/OpenRA/OpenRA) 的 Shroud/VisibilityType 相关接口，依赖其 C# Actor/Trait/World 运行时，不能直接作为本项目 GDScript 状态层依赖。本轮维护现有 MechVisionSystem，未引入或重写视线算法，也未移植外部代码。

实际复用原有半径遍历、MechGridState.terrain_line_clear、LOS 源缓存、PackedByteArray 原生复制和两处既有三态迷雾绘制。项目改动仅为业务顺序：半径内先写探索记忆，LOS 合格格再叠成实时可见；同次更新先投射再复制记忆，避免新灰格延迟出现。普通损血不影响源签名，未增加全图扫描或额外射线。

## 25. 二级建造目录（2026-11-08）

先评估[RTS Framework](https://github.com/rluders/rts-framework)（MIT，完整3D Node框架，维护者标注WIP），其选择/命令/建筑生命周期与本项目纯数据模拟和既有HUD不匹配，不为菜单引入完整框架。实际直接复用Godot原生[ButtonGroup](https://docs.godotengine.org/en/stable/classes/class_buttongroup.html)、[GridContainer](https://docs.godotengine.org/en/stable/classes/class_gridcontainer.html)、[ScrollContainer](https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html)和JSON资源导入。项目只负责目录分类、展示状态及原有建造意图接线；未移植外部代码或自写布局/滚动/互斥按钮算法。

## 26. 0.5.89 生命周期修复（2026-11-09）

核对 [OpenRA](https://github.com/OpenRA/OpenRA)（GPL-3.0，C#/SDL 完整 RTS 引擎）：其 Actor/Trait/World 运行时不适合作为本项目纯 GDScript 模拟的直接依赖。本轮没有移植或重写其算法。直接复用项目现有的 Godot [AStarGrid2D](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html)、NavigationServer2D 避让、交易与命令模块；仅修正闸门通行参数、驻防命令生命周期、真实付款/退款归属和终波展示状态。没有新增寻路、避让或预算求解算法。

## 27. 新敌人运行接入（2026-11-09）

检索官方Godot示例与GDQuest Steering AI后，继续直接复用项目已接入的原生AStarGrid2D、WorkerThreadPool、Resource、现有Steering vendor和MechMarchField。没有从外部框架移植或重新实现导航算法。项目新增部分为敌人数据、阶段/配额编成及战斗状态适配；候选来源、复用边界和验证见[接入记录](../validation/enemy-integration.md)。

## 28. 三维表现迁移首阶段（2026-11-09）

实施前重新检索[官方示例](https://github.com/godotengine/godot-demo-projects)（MIT）和[RTS Framework](https://github.com/rluders/rts-framework)（MIT，WIP）。完整RTS框架绑定自己的Controller/SelectionManager/节点化单位，不作为本项目模拟、导航和命令层的替代依赖；没有复制或按其源码重写算法。官方示例用于查找原生能力的适用范围，目前未下载具体示例源码，不宣称源码已复用。Agent-Reach当前工具不可用，使用网页检索。

实际直接使用Godot原生Camera3D正交投影/射线/屏幕投影、Plane/AABB求交、Geometry2D裁剪/三角化、SurfaceTool、BoxMesh/CylinderMesh、MultiMeshInstance3D、ImageTexture与现有快照/HUD。自写部分为地图坐标、镜头手势、快照到模型批次的绑定、预览及迷雾材质接线；不新增相机投影、求交、寻路或避让算法。兼容渲染器保持不变，具体阶段和验证边界见[迁移方案](3d-presentation-migration.md)。
