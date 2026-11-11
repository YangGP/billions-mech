# 文档索引

更新于 2026-11-11，对应 **0.5.90-dev**。默认三维入口已启用；交互、整局与综合性能仍待验收。运行与键位见根目录 [README](../README.md)。

> 设计命名：原“燃料”改为**碳晶**（有机-无机混合固体燃料），原“稀有晶体”改为**超导矿**。UI 显示名已切换；运行 Resource ID 仍为 `fuel` / `crystals`。

## 从哪里开始

| 目的 | 入口 |
| --- | --- |
| AI 开发规范与节省 token 提示词 | [AGENTS.md](../AGENTS.md) |
| 完成度、缺口与下一步 | [当前开发计划](development-plan.md) |
| 二维逻辑与三维表现边界 | [三维迁移方案](3d-presentation-migration.md) |
| 验证三维操作与生命周期 | [三维人工清单](../validation/3d-manual-checklist.md) |
| 查看三维性能结论 | [三维交互与性能](../validation/3d-interaction-performance.md) |
| 交给其他 AI 继续实现 | [开发任务与验收规格](ai-development-handoff.md) |
| 查当前运行数值 | [数值表](values.md) |
| 验证入口与证据 | [验证索引](../validation/README.md) |

## 系统规则

| 文档 | 范围 |
| --- | --- |
| [资源与供给](resources.md) | 五项库存、容量、电力、覆盖、冷却、环境发电和合金加工 |
| [建造经营](building-economy.md) | 下单、施工、升级、维修、拆毁、基座、生产、驻防和预算 |
| [操作交互](operations.md) | 现行键位、菜单、暂停、镜头、HUD 和区域选择 |
| [地图地形](map-terrain.md) | 128×128 开发图、矿点、风口、水域、出生与退守空间 |
| [敌种与波次](waves-enemies.md) | 游荡、噪声、行军、预告、精英、感染和终波 |
| [视野迷雾](vision-fog.md) | 无遮挡探图、实时 LOS、信息过滤和视野外降频 |
| [代码架构](architecture.md) | 模拟/表现边界、命令、缓存与规模目标 |
| [模块接口参考](module-interfaces.md) | 类、公开方法、命令 payload、快照字段与视图契约 |
| [模块复用调研](reuse-research.md) | 来源、许可证、采用与不采用结论 |

## 设计基准与待开发提案

| 文档 | 状态 |
| --- | --- |
| [基础设定](game-design-concept.md) | 产品方向结论 |
| [建筑目录 V2](building-roster-v2.md) | 当前建筑与升级基准；B07 风冷已实施 |
| [机械敌人设计稿](enemy-roster.md) | 当前敌人阵容与机制方向，部分已接入 |
| [玩家兵种设计稿](player-roster.md) | 六兵种：3 基础 + 3 高级；已接入运行代码 |
| [全图打击设计稿](strategic-strike.md) | 战略火力提案，未接入 |

## 维护规则

- 完成度只维护在[开发计划](development-plan.md)。
- 当前人工验收只维护在[三维人工清单](../validation/3d-manual-checklist.md)。
- 历史流水、阶段性实现记录和一次性截图已清理；需要时从 Git 历史查询。
- 当前规则查系统专稿，当前数值查数值表；设计提案不等于已实现。
