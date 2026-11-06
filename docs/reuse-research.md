# 模块复用：已有方案调研

> 调研日期：2026-11-04～2026-11-06。版本：0.4。\
> 范围：支撑 architecture.md 的模块复用选型；本稿是来源核对和建议，不表示候选已接入或完成适配/性能验证。\
> 已确认原则：新建项目，旧原型实现不再使用；外部模块能复用就复用，不能复用先找其他已有方案。开发顺序见 development-plan.md。
> 历史口径：§4 记录 M3 单钱包实现时的选型依据；新版设计已加入多资源与采矿，扩展任务见开发计划。该记录不限定当前设计的资源范围。

## 1. 结论

从空的 2D 等距工程开始；比较 Godot 内置能力、RTS Advanced Lite 的可适配模块与其他已有方案。旧原型代码、场景与内容定义不纳入候选。只有确认外部方案不适合后，才实现本项目特有规则。

## 2. 模块复用入口

这些是检索到的已有候选，不是已经选定的新框架。每个来源均须核对维护情况、许可证与 Godot 4.7 兼容性，不能仅凭 README 或星数决定采用。

| 模块 | 优先复用来源 | 不能复用时的已有候选 | 当前结论与限制 |
|---|---|---|---|
| 2D 等距镜头、地图坐标、建造预览、时钟 | Godot 内置 2D/网格能力与外部可适配模块 | Crusade 的等距镜头/地图实现；其他固定步长/放置方案按功能检索 | M1–M3 已使用原生固定物理步、Camera2D 与项目坐标/预览适配；Crusade 要求 4.4.1，未导入其场景运行时 |
| 选择集合、编队、输入绑定、队列/阵型语义 | RTS Advanced Lite | rluders/rts-framework 的 SelectionManager/CommandManager；Crusade 的选择与单位控制 | Lite 是 3D，选择投影与地面拾取必须检查；其他候选也有各自实体/场景依赖，不表示已经适配 2D sim |
| 玩家单位与局部战术 A* | 可脱离场景树的已有寻路实现 | Godot 内置 AStarGrid2D | M2 已接入原生 AStarGrid2D，M3 支持建筑占用变更后的重建与路径更新；正式单位和规模性能仍待 M4/M5 |
| 小地图 | 先查已有 2D 小地图方案，Lite 无此模块 | Razoric480/godot-minimap-demo | 新工程需接入或实现；该候选为旧演示项目，Godot 4.7 接入与素材许可仍需核对；不直接导入素材 |
| 机潮流场 | 先查已有 Godot 流场实现 | Crusade 的流场与局部避让实现 | 已 vendor Crusade `flow_field.gd` + `steering.gd`（§9，HEAD e4929c8，MIT 逐字未改）；walkable 注入地形层，建筑阻挡由移动/攻击处理；游荡敌走既有 AStarGrid2D |

每项正式采用前记录：源 URL、许可证原文位置、版本/提交 SHA、引擎依赖、需修改的接口、已知问题、适配验证结果。可复用模块锁版本入 vendor；未选候选不导入工程。

## 3. 一手来源

- [RTS Advanced Lite README](https://github.com/openclawaimac/godot-rts-advanced-lite#readme)：3D 基座、Lite/Pro 能力边界、MIT。
- [Crusade README](https://github.com/saman-mb/crusade-rts#readme)：MIT、2D 等距地图/镜头/选择、流场候选与 Godot 4.4.1 要求。
- [Crusade src/core/flow_field.gd](https://github.com/saman-mb/crusade-rts/blob/main/src/core/flow_field.gd)：已 vendor 的流场核心一手源码（§9）。
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
| [Mindustry ConstructBlock](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/world/blocks/ConstructBlock.java) | GPL-3.0；Java、物品供料与世界建筑生命周期依赖 | 借鉴独立建造状态、取消与完工切换的设计；本项目为预付单钱包、并行时间施工，不复制源码 |
| [OpenRA RepairableBuilding](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/Buildings/RepairableBuilding.cs) | GPL-3.0；C# Actor/Trait 与玩家经济依赖 | 参考模拟 tick 中小步扣费与修复的成熟做法；不复制源码，不接入其运行时 |
| [Godot Geometry2D](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html) | 随引擎提供 | 直接复用 `bresenham_line` 生成墙线，预览与提交用同一组逻辑格 |
| [Godot ConfirmationDialog](https://docs.godotengine.org/en/stable/classes/class_confirmationdialog.html) | 随引擎提供 | 直接复用拆除确认弹窗；继续复用原生 Camera2D、AStarGrid2D、Resource、Control 与进度条 |

生命周期与维修参考的是上述项目的设计，没有将 GPL 源码引入仓库；未产生需锁版本的第三方代码依赖。建筑参数使用原生 `.tres` Resource；预付预留、容量恢复例外、施工与血量独立是本项目 sim 规则。M3 未验证 M5 机潮性能，也不据此改变后续流场选型。

## 5. 新版经济与采矿（2026-11-05）

比较高星、持续维护的 [Mindustry Drill](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/world/blocks/production/Drill.java)（GPL-3.0，Java / Block / 物品及液体依赖）与 [OpenRA ResourceLayer](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/World/ResourceLayer.cs)（GPL-3.0-or-later，C# / World / Trait / 地图依赖）。参考覆盖矿格校验、独立资源层与储量变化的职责划分；两者均不能直接作为纯数据 GDScript 模块接入，未复制源码或素材。

实际复用 Godot Vector4i 保存币/矿石/金属/稀有的固定分量，Resource 保存建筑与矿点初值，沿用现有固定步长、串行命令和视图。有限矿点、一站一矿、逐资源预付退款及每分钟余数累积由本项目 sim 装配，无新增第三方依赖。Agent-Reach 仍未安装，使用网页检索与一手源码核对。所有实体继续使用几何白模，无新美术依赖。

## 6. M4 生产与单位（2026-11-05）

复核 [RTS Advanced Lite README](https://github.com/openclawaimac/godot-rts-advanced-lite#readme)（MIT，3D 选择/阵型/分离/生产）和高星项目 [OpenRA ProductionQueue](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Traits/Player/ProductionQueue.cs)（GPL-3.0-or-later，C# Actor/Traits、独立队列与预付选项）。Lite 的地面拾取/影子节点仍依赖 3D 适配，OpenRA 依赖其世界与规则运行时，均不直接导入。

选择继续复用原生 Rect2/Geometry2D、AStarGrid2D 与现有串行命令；新增纯数据生产队列、单位状态和客户端选择集合。移动复用原生 A*，局部占位用格桶，等待后暂时屏蔽其他单位格重新求路；生产扩展本项目已有账本及预留事务。未复制第三方源码，未产生新 vendor 或许可证依赖；未将 4 单位训练场视为最终规模性能验证。

### 窄口拥堵：直接采用原生 RVO（2026-11-06）

用户反馈主脑与组装厂之间易卡住。初版把友军当硬碰撞，堵塞后再封掉友军整格。此前修补仅参考设计、自写侧让和软分离，未达到直接使用成熟方案的要求，现已删除。

| 比较来源 | 实现与依赖 | 本轮决定 |
|---|---|---|
| 高星、持续维护的 [Godot NavigationServer2D](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html) | 引擎自带 RVO2；RID、物理帧速度回调与静态障碍接口；不要求单位成为场景节点 | **直接调用原生求解器**；继续直接使用原生 AStarGrid2D，不额外移植避让算法 |
| 高星、持续维护的 [OpenRA Move](https://github.com/OpenRA/OpenRA/blob/bleed/OpenRA.Mods.Common/Activities/Move/Move.cs) | GPL-3.0，依赖 C# Actor/Locomotor 运行时 | 不导入；其等待/让路设计不能算作本项目已直接复用实现 |

已核对 Godot 4.7 分支的 [NavAgent2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/navigation_2d/nav_agent_2d.cpp) 与 [NavMap2D](https://github.com/godotengine/godot/blob/4.7-stable/modules/navigation_2d/nav_map_2d.cpp) 一手源码。实际运行依赖为本机 Godot 4.7.2 `ed1daf0bf`，引擎 MIT，内置 RVO2 为 Apache-2.0，见 [版权清单](https://github.com/godotengine/godot/blob/4.7-stable/COPYRIGHT.txt)。没有复制或修改求解器源码，也没有新增 vendor。

`sim/crowd_navigation.gd` 是 API 适配层：提交逻辑坐标/期望速度，注册单位与建筑/地形障碍，收齐原生回调后批量落地。暂停停用专属地图；命令使旧批次失效；重开/退出释放 RID；仅瞬移时清零原生速度状态。指令、A* 路点跟随、地形减速和最终静态碰撞校验仍由项目负责，避让方向与速度由原生 RVO 求解，没有自写侧让/推挤回退。

后续目标漂移反馈修正的是项目指令适配：友军临时占位不再替换点击格/阵型终点；最后路点在原生位移实际提交后确认，空路径重试原目标。单兵静态不可达时拒绝下令，不寻找附近替代终点。求路与避让仍分别直接调用原生 AStarGrid2D 与 RVO，没有新增避让或寻路算法。

按 [官方回调时序](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationservers.html)，提交发生在固定物理帧，移动提交和视图刷新在同帧的原生回调收齐后执行，不在每个单独回调中各自刷新。已知限制：RVO 不能保证所有拥堵场景都能解开，[官方说明](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html) 提示完全对称的迎面情形可能失败。这里只完成 29 个脚本的语法核对，通行、暂停和资源生命周期仍须运行复验，不能把接入成熟求解器写成已通过玩法验收。

## 7. 是否改用 RTS Advanced Lite：核查与决定（2026-11-06）

用户要求核查功能是否使用 RTS Advanced Lite，未使用则改为该框架实现。核查结果：全部 29 个脚本均为自有 `Mech*` 类（继承 Godot 原生 RefCounted/Node2D/Camera2D/CanvasLayer/Resource），无 vendor 目录与 Lite 引用；选择/编队、生产队列、单位战斗为自有 2D sim/客户端实现，寻路直接调用 AStarGrid2D，避让直接调用 NavigationServer2D RVO（§6）。

经用户确认维持现状、不改用 Lite，决定依据记录如下：

- 现行实现已直接复用引擎内置成熟方案（AStarGrid2D、NavigationServer2D/RVO2、Geometry2D、Camera2D），符合 AGENT.md"直接复用引擎内置能力"的要求。Lite 为 3D 场景节点基座，选择投影/地面拾取/单位模块接入 2D 等距项目须按本作改写；按 AGENT.md 口径，仅参考设计后自行重写不算复用。
- Lite 不含本项目最大系统：建造、多资源经济、电力覆盖、容量、采矿、波次（§4 已核对"没有可直接接入的建造经济模块"）。
- architecture.md 红线要求 SimCore 不 import 场景/节点类型（无头 sim）；Lite 单位与选择耦合场景节点，直接接入破坏该边界。
- 主脑/组装厂窄口拥堵已用原生 RVO 修复（§6），换用 Lite 的分离避让会回退该修复。
- 本地环境无 Godot，整框架替换后无法执行任何校验；不做不可验证的替换。
- 后续未实现模块（键位重绑定、小地图等）仍按 §2 流程逐模块评估 Lite 与其他候选；采用前照常记录来源、许可证、版本与适配验证结果。

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

## 9. M5 机潮行军流场选型（2026-11-06）

需求（architecture.md §5）：未接敌机潮向主脑行军用流场——只读地形、不因建墙/墙塌重算；建筑阻挡由移动/攻击处理；接敌后切 sim 侧 A*；接敌判定/分离走空间分区。按用户指示扩大到非 Godot 生态与 C#（Godot 原生支持 .NET），共核对五个候选后定稿，不再扩大检索：

| # | 候选 | 形态 | 许可证 / 维护 | 结论 |
|---|---|---|---|---|
| 1 | [Crusade RTS](https://github.com/saman-mb/crusade-rts) `src/core/flow_field.gd` + `steering.gd` | Godot 4.4 GDScript，纯 RefCounted，带 headless 单测与 CI | MIT ©2026；HEAD `e4929c8`（2026-07-26，PR #263 仍在演进） | **直接 vendor 复用**（下详） |
| 2 | [godot-tilemap-flowfields](https://github.com/arnemileswinter/godot-tilemap-flowfields) | Godot 3.5 GDNative：Rust 核心 + 预编译 .so/.dll，FlowFieldGenerator 节点读 TileMap | MIT ©2022；v0.1.0 早期 | 不采用：引擎版本（3.5 vs 4.7）、原生二进制依赖（本项目纯 GDScript）、节点/TileMap 耦合违反无头 sim 红线 |
| 3 | [openage pathfinding](https://github.com/SFTtech/openage)（libopenage/pathfinding，v0.6.0） | C++/Python 引擎级：扇区/门户分层 A* + 逐扇区流场，源自 Elijah Emerson 流场砖文章 | **GPLv3**；成熟引擎项目 | 仅参考设计：GPL 不可 vendor、不复制源码；其 FLOW_LOS/波前受阻标记与字段缓存复用留作后续规模优化参考 |
| 4 | [bevy_pathfinder](https://lib.rs/crates/bevy_pathfinder)（v0.1.2） | Rust crate：BFS 流场（多目标 O(1) 查询）+ 哽喉点检测 FlowGate + 共享 A* | MIT；2026-09 仍发版 | 仅参考：Rust 需 GDExtension 工具链，与纯 GDScript 边界冲突；哽喉点检测留作后续雷达/伏击玩法候选 |
| 5 | [Pathfindax](https://www.nuget.org/packages/Pathfindax) | C# 寻路框架（A*/Dijkstra/PotentialField/FlowField），耦合 Duality 引擎 | 最后更新 **2019-09-01**，仅 .NET Framework 4.7.2 | 不采用：7 年未维护，目标框架无法直接用于 Godot .NET（须整体移植），接入即等于参考后自写 |

引擎内置核对：NavigationServer2D 提供逐 agent 寻路与 RVO 避让、AStarGrid2D 为逐 agent A*，Godot 4.7 无内置流场能力，不存在可直接复用的内置方案。C# 生态按用户要求专门核对（NuGet Tags:"PathFinding" 全表 + Unity 生态检索）：唯一带 FlowField 的 C# 库即 #5 Pathfindax（2019 年停更），Unity 侧只有教程文章代码、无维护库——**引入 C#/.NET 工具链缺乏可维护的成熟模块支撑**，且会为用户验证链增加 dotnet 构建步骤；若日后出现活跃维护的 C# 候选，再按 §2 流程单独评估。

### 采用：vendor/crusade（锁版本 HEAD `e4929c8`，MIT）

已按 AGENT.md"直接复用"要求拉取本地副本（`d:\fish\crusade-rts\`，项目同级不参与导入）逐文件分析后，vendor 两个纯逻辑文件入 `vendor/crusade/`，逐字未改：

- **`flow_field.gd`**：均匀成本 4 连通 BFS 积分场（PackedInt32Array 扁平缓冲，`recompute(goal)` 复用）+ 8 邻最低成本流向向量；可通过性经构造器 `walkable: Callable` 注入。本项目注入"地形层可通过、不含建筑"，即满足"只计地形，玩家建筑由实际碰撞/攻击处理"；附 headless 单测，仅依赖核心类型。
- **`steering.gd`**：纯静态分离（逆距离权重、NaN/重合防护）与期望速度合成；配合本项目网格桶邻居表即满足"分离使用空间分区"。

不导入部分：`flow_follower.gd` 耦合 Crusade 等距/高程几何（EntityPlacement/IsoCoord），且墙卫语义为"贴墙滑动"——与本项目"撞墙打墙"（建筑阻挡切攻击）规则冲突；其"步进逐级降级、绝不站进实体格"守卫思路在敌方行军集成中吸收。其余 A*/阵型/编辑器模块本项目已有对应实现。

已知限制与适配口径（详见 `vendor/crusade/README.md`）：均匀成本 BFS 下崎岖地不比开阔地贵，敌人不因崎岖绕路、仅移动层减速——与 map-terrain.md §3"主口前天然迟滞"意图一致；`flow_at` 对角流向无防切角守卫，敌方行军集成在步进校验中对齐玩家 A* 的 DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES 语义；主脑固定 + 地形静态 ⇒ 波次流场整局只算一次；游荡敌不共用主脑流场，数量小（切片图 ≈17 + 回填）直接走既有 AStarGrid2D。

本地参考副本：`d:\fish\crusade-rts\`、`d:\fish\godot-tilemap-flowfields\`（与 Lite 副本同级，不参与本项目 Godot 扫描）。godot-tilemap-flowfields 的 algo.rs 存在流场生成误用 SouthWest 邻居值充当 NW 的缺陷（`native/src/algo.rs` L242），引用其思路时须知。vendor 文件的 Godot 4.7 语法检查与实机行为验证由用户开发环境执行，通过前不记为已验收。

## 10. 巨量单位 RTS 架构对照（2026-11-06，M5 出兵切片前）

按用户要求，在出兵切片动工前核对巨量单位 RTS 的成熟架构，共五个参考；全部为设计对照，无代码引入（GPL/闭源/异构运行时，无一可 vendor）：

| 参考 | 规模与形态 | 对本项目的印证与差异 |
|---|---|---|
| [RecoilEngine](https://github.com/beyond-all-reason/RecoilEngine)（Spring 后继，BAR 引擎） | 设计目标 ~1 万并发单位、实测 ~1.77 万；C++23，固定 30Hz 确定性模拟层 + `for_mt` 多线程 + 四叉树寻路（HAPFS/QTPFS）+ 渲染帧间插值 | 30Hz 固定步长确定性模拟与本作一致；但其规模靠多线程并行，GDScript 无此路线，本作规模治理仍按架构稿 §9（分区休眠/迷雾外降档/降速阀）。BAR PvE 层（Scavengers/Raptors gadgets）给出波次系统成熟形态：grace period 静默（120–360s 按难度）、anger 进度（时间+玩家经济驱动）、数据驱动波次表（`configs/scav_spawn_defs.lua`）、波内 squad 编组与冷却 |
| [Mindustry](https://github.com/Anuken/Mindustry)（GPL-3.0，Java） | 数千单位，单线程主循环 | **与本作同构**：波次方共享"向核心的流场"（`Pathfinder.preloadPath(getField(waveTeam, costGround, fieldCore))`），`SpawnGroup` 数据驱动波次构成（begin/spacing/unitScaling/max）。差异：其移动成本把玩家建筑血量折成软成本烘进流场（增量更新，敌人择最薄墙突入）；本作按架构稿走地形-only 场 + 撞墙接敌（TAB 口径、零重算）——记录为已知备选，不采用 |
| [openage](https://github.com/SFTtech/openage)（GPLv3） | AoE2 引擎重制：扇区/门户分层 + 逐扇区流场 | 分区休眠（架构稿 §9）的蓝图来源；流场缓存/复用思路供后续噪声目标场参考（§9 已记） |
| [OpenRA](https://github.com/OpenRA/OpenRA)（GPL） | 中规模 lockstep RTS，Actor/Trait | 命令即意图、tick 串行执行——与本项目命令队列同构（§4/§6 已记） |
| Supreme Commander（闭源） | 500 单位/边设计上限、战略缩放 | 仅设计标尺：证明 1–2k 是"可玩规模"常规区间；无实现可引 |

结论：本作"无头固定步长模拟 + 命令队列 + 波次流场 + 空间分区"与上述主流实现**同构**，不存在需要推翻的架构性差异；Recoil 的多线程路线明确不适用于 GDScript。出兵切片据此确认两个实现口径：**波内分批出生**（BAR squad/冷却思路的简化版，避免单 tick 批量插入的峰值）；**波次配置数据驱动**（对标 SpawnGroup/波次表，本作即数值稿 §12 预算曲线，不写死在代码）。
