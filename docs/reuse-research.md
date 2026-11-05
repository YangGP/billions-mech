# 模块复用：已有方案调研

> 调研日期：2026-11-04～2026-11-05。版本：0.4。\
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
| 机潮流场 | 先查已有 Godot 流场实现 | Crusade 的流场与局部避让实现 | 只作候选；必须满足“只计地形，玩家建筑由实际碰撞/攻击处理”以及纯数据 sim 边界 |

每项正式采用前记录：源 URL、许可证原文位置、版本/提交 SHA、引擎依赖、需修改的接口、已知问题、适配验证结果。可复用模块锁版本入 vendor；未选候选不导入工程。

## 3. 一手来源

- [RTS Advanced Lite README](https://github.com/openclawaimac/godot-rts-advanced-lite#readme)：3D 基座、Lite/Pro 能力边界、MIT。
- [Crusade README](https://github.com/saman-mb/crusade-rts#readme)：MIT、2D 等距地图/镜头/选择、流场候选与 Godot 4.4.1 要求。
- [RTS Framework README](https://github.com/rluders/rts-framework#readme)：MIT、选择与命令模块及其场景依赖。
- [AStarGrid2D 官方文档](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html)：内置 2D 网格寻路接口。
- [Godot Minimap Demo README](https://github.com/Razoric480/godot-minimap-demo#readme)：MIT 代码仓库与 2D 小地图表示演示；不据此认定演示素材均可沿用。

调研方式：检查项目与官方源码/README/issue。本环境未找到 Agent-Reach 命令，改用可用的网页检索和一手源码；未导入、执行或复制任何候选依赖。

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
