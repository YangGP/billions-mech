# 代码架构（首切片骨架）

> 技术基线：**Godot 4.7、GDScript、2D 等距、模拟/表现分离**。本稿定义目标架构；实现进度与待明确规则见 [开发计划](development-plan.md)，选型结论见 [复用调研](reuse-research.md)，玩法来源见 [文档索引](README.md)。

## 1. 外部模块接入边界

输入/镜头/选择模块只能接表现层；战斗/队列/寻路适配后接 sim，先验证能否脱离原场景树。采用流程与候选清单统一维护在复用调研中。

## 2. 架构总览

```
┌─ 表现层 Presentation（Godot 场景树、输入、镜头与视图）────┐
│  渲染节点 / HUD / 输入捕获 / 放置模式客户端状态机           │
└──────────┬──────────────────────▲─────────────────────────┘
      命令（下发）           事件 + 状态查询（只读）
┌──────────▼──────────────────────┴─────────────────────────┐
│  命令层 CommandQueue（到达即执行，含暂停期）                │
├───────────────────────────────────────────────────────────┤
│  模拟核心 SimCore（固定 tick，可无头运行）                  │
│  ├ Grid 网格（地形/占用/供电覆盖/成本场/迷雾）               │
│  ├ 规则系统：账本/采集/容量/电力/建造/生产/威胁/战斗/视野   │
│  └ EventBus（模拟内部事件）                                │
├───────────────────────────────────────────────────────────┤
│  内容数据 Defs（Godot Resource：.tres）                     │
└───────────────────────────────────────────────────────────┘
```

**单向依赖**：表现层 → 命令层 → SimCore；SimCore 不 import 场景/节点/渲染类型，模拟可无头运行。

单位为注册表中的纯数据，场景树只放渲染/选择用的影子节点。

M4 玩家单位的局部避让直接使用 Godot NavigationServer2D / RVO，适配层只持有 RID，不创建单位场景节点。每个固定物理帧提交位置/期望速度，在同帧原生回调收齐后批量提交移动、刷新视图；暂停使待收结果失效并停用专属地图，重开/退出释放服务器资源。无头运行仍需引擎物理帧调度。来源与已知限制见 [复用调研 §6](reuse-research.md)。

## 3. 核心原则

1. **一切玩家行为皆命令**：建造、取消、拆除、维修开关、集结点、单位指令、生产下单——全部经短生命周期 CommandQueue 校验与提交，不持久化录制。
2. **暂停只冻结 tick**：命令仍即时校验与提交；施工、收入、波次、战斗和移动停止推进，表现层视觉动画可继续（operations.md §3.3）。
3. **数据驱动内容**：BuildingDef 字段与 building-economy.md §10 参数槽一一对应；敌种/波次同理。平衡调整不改代码。
4. **固定步长与整数资源**：收入/采集保留余数累积，暂停不推进；数值使用 values.md 的单位，不将每分钟产率误作每秒。

## 4. CommandQueue 命令层

- 命令结构：`{type, payload, seq}`；每条命令两个校验点：
  - **入队前 UI 快检**（廉价，驱动按钮灰显/放置预览着色）；
  - **执行时权威校验**（真实，拒绝则回执 UI 报错）。
- 两个校验调用**同一个纯函数**（`validate_placement`，见 §5 建造）——UI 与模拟永不各写一套规则。
- 首切片命令集：PlaceBuilding / CancelConstruction / Demolish / CancelDemolish / ToggleRepair / SetRally / QueueUnit / CancelProduction / IssueMove / IssueAttackMove / IssueAttack / TogglePause（元命令）。
- 单位类命令（IssueMove/Attack/AttackMove）入队后由 **sim 移动/战斗系统执行**，序号用于串行处理与回执；阵型/避让的外部适配待选型，不引入命令录制。

## 5. Grid 与规则系统

- **空间数据**（同尺寸方格网）：地形层（三类 + 建造许可，map-terrain.md §3）/ 占用层（格→EntityId）/ **供电覆盖层**（bool + 来源标记）/ 成本场。视野为第五层，见 vision-fog.md §7；矿点另外保存类型、储量与采集绑定，不混作建筑占用。
- **供电覆盖传播**：主脑/中继源 BFS；中继被毁 → 区域失效并级联下游（resources.md §6）；脏标记增量重算。
- **放置校验管线**：building-economy.md §3.2 六步（地形→覆盖→重叠→电力→容量→资源），预览/命令快检/执行共用。最后一步检查币/矿石/金属/稀有并一并支付；采集站另检查矿点绑定，具体边界须在接入前补齐。
- **系统联动**：sim 协调事务内校验与提交，完成后通知视图；事件总线不替代事务边界。下表为目标职责拆分。

| 系统 | 职责 | 对应设计 |
|---|---|---|
| Ledger 账本 | 多资源库存、主脑/节点产币、支付/退款 | resources.md §3–§4、values.md |
| ExtractionSystem 采集 | 矿点绑定、被动采集、储量消耗与耗竭停产 | resources.md §4、map-terrain.md §4 |
| CapacitySystem 容量 | 提供/占用登记、超载判定、查询 | resources.md §5 |
| PowerSystem 电力 | 容量预留、覆盖传播、断供/级联/恢复 | resources.md §6 |
| ConstructionSystem 建造 | 校验管线、并行施工、血量爬升、退款、维修、拆除 | building-economy.md §3–§4 |
| ProductionSystem 生产 | 队列、付款占容、集结点 | building-economy.md §5 |
| WaveDirector 波次 | 首波触发、威胁预算、边缘出生、定性预告 | waves-enemies.md §2–§6 |
| Threat / Noise | 游荡敌回填、噪声聚拢、感疫生成与脉冲 | waves-enemies.md §4/§8.1 |
| CombatSystem 战斗 | 索敌、原型机庇护/跨墙/攻城、建筑目标与接敌 | waves-enemies.md §8、vision-fog.md §5 |
| VisionSystem 视野 | LOS、实时视野源、覆盖探索、三态迷雾 | vision-fog.md |
| WinLoseCondition | 主脑被毁判负、切片清场/终波守住判胜 | game-design-concept.md §3/§6 |

- 约束联动示例：中继被毁 → PowerLost → 覆盖内节点容量提供归零 → CapacitySystem 重算 → CapacityOverloaded → UI 警报。
- **寻路分工（按状态分轨）**：
  - **机潮行军（未接敌）= 加权流场**：波次目标为主脑；积分场按 **地形权重 × 建筑软成本** 计价（数值稿 §11：建筑格 1 + min(HP,400)/8、施工中按当前 HP、主脑豁免——Mindustry Pathfinder 口径）。缺口足够便宜时敌人自动弃墙走缺口；无近路时场仍指向墙，步进被建筑挡住即接敌啃墙。占用层变化（建/拆/毁）即时重算，纯 HP 漂移（墙被啃）限频 1s 重算。游荡敌按噪声目标趋近，目标场与缓存方案待选，不能强制共用主脑目标。
  - **机潮接敌 = sim 侧 A\***：进入攻击范围或被攻击时切出流场，做局部战术机动；脱离接敌（目标死亡、周围无敌）→ 回流场继续向主脑。
  - **玩家单位 = sim 侧 A\***：目标任意、数量少（容量约束保证），始终走 A\* 库。
  - **接敌判定必须空间分区**（网格桶，§9 规模的硬前提）：Marching/Engaged 切换的三条件见 vision-fog.md §5，判定半径为参数槽；实现上按桶内近邻查询，禁止全表扫描。
- 状态机：`Marching(流场) ⇄ Engaged(A*)`，切换判定归 CombatSystem。

## 6. 表现层对接（Godot 侧）

- **放置模式**（operations.md §3.2）是纯客户端状态机：幽灵预览调 `validate_placement` 着色，点击产出 PlaceBuilding 命令；拖拽连放在客户端聚合为批量命令。
- **HUD 读模型**：资源条/波次槽/警报直接查询 SimCore 只读接口；波次强度预告位吃 WaveDirector 的 payload（operations.md §8）。
- **现行失败边界**：主脑移除时锁定会话失败，暂停既有时钟、作废并停用原生移动；本局玩法命令全部拒绝，只放行重开/载入场景。镜头与查看不暂停场景树。有限波次胜利随后接入。
- **暂停视觉**：订阅 TogglePause 元命令，降饱和 + 常驻标识；模拟已被 tick 闸门冻结，表现层纯视觉动画可继续。
- **单位视图 = 纯影子节点**：实体注册表 ↔ 节点映射表；未来选择/框选作用于影子节点，经映射表解析为 EntityId 后下发命令，节点只读不写。
- 建筑视图同构（订阅 EventBus + 脏标记同步）。

## 7. 内容数据（Def ↔ 参数槽映射）

| Def | 字段（= building-economy.md §10 参数槽） | 格式 |
|---|---|---|
| BuildingDef | id、C/Co/Cm/Cr、T、HP、K、P、+C、+P、R、+coin/+ore/+met/+rare、S、F、占格、分类、解锁幕 | .tres |
| UnitDef | id、币/料造价、生产时间、HP、攻击、攻速、射程、移速、K 占容 | .tres |
| EnemyDef | id、HP、攻击、移速、地形标签、伤害修正表 | .tres |
| WaveDef | 编号、时间或触发、构成（EnemyDef×数量）、出生带选择、强度预告文本 | .tres |
| MapDef | 地形网格、主脑出生点、主口标记、矿点类型/坐标/初始储量 | 自定义 Resource |

## 8. 首切片事件清单

目标事件：BuildingPlaced / ConstructionCompleted / BuildingDestroyed / ConstructionCancelled / Demolished / PowerLost / PowerRestored / CoverageChanged / CapacityOverloaded / CapacityRecovered / ResourceDepleted / WaveIncoming（定性强度 + 方向，不含精确数量/构成）/ WaveSpawned / WaveCleared / NoiseEmitted / InfectionTriggered / VisionChanged / UnitProduced / UnitDied / MainbrainDestroyed（= 失败）/ SliceVictory（切片终点）。名称为接口草案，不代表已全部实现。

## 9. 设计规模（非功能需求）

> 设计目标量级，是流场、模拟/表现分离和空间分区的设计依据，性能验证以此为基准；不是生成硬上限，尚未完成规模验证。

| 维度 | 目标 | 架构后果 |
|---|---|---|
| 机潮同波在场 | **1–2k**（留性能余量） | 行军必须流场；接敌判定/分离/索敌必须空间分区（网格桶），禁止 O(n²) |
| 玩家单位 | **200–300** | sim 侧 A\* 与避让须按目标数量验证；容量系统提供玩法约束 |
| 建筑总数 | **约 300–500**（墙段为主，估计值） | 覆盖/占用层必须脏标记增量更新；拖拽连放必须批量下单 |
| 同屏实体合计 | 数千（感疫连锁时可能尖峰超出） | 影子节点零逻辑纯视觉；选择/框选经映射表，不承担计算 |

**规模治理策略**：

- **分区休眠**：无威胁区块（无敌情、无玩家单位、无噪声源）的敌人进入低频模拟（数 tick 一跳），有事件唤醒。
- **迷雾外降档**：视野外敌人降低更新频率与寻路精度，与视野系统同批实现（vision-fog.md §7）。
- **降速阀**：负载超阈值时整体放慢 tick，表现为大场面慢动作。
- 感疫、波次、游荡敌回填不设数量闸，以运行时治理消化规模。

## 10. 目录结构（Godot 项目）

```
/sim                       # 纯逻辑：grid、power、capacity、construction、waves、ledger、events、defs
/commands                  # 命令定义 + 队列 + validate_placement
/content                   # .tres：buildings/ units/ enemies/ waves/ maps/
/presentation              # 放置模式、HUD、建筑视图
/scenes                    # 固定主场景、HUD 子场景
/validation                # 实施和检查记录
/archive                   # .gdignore 排除的历史资料与旧资源
```

## 11. 非目标

- 不做联网/多人。
- 正式存档另排；没有回放需求，不加入命令录制、状态哈希或回滚。
- 不做区域层执行（新命令类型 + 新系统即可接入，不改核心）。
- 不做 Mod 工具链（数据驱动天然开放，编辑器不做）。
