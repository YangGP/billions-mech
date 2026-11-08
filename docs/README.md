# 文档索引

规则查系统专稿，数值查数值稿；当前进度、设计/实现差异和开发顺序统一查开发计划，运行方法与现行键位查根目录 [README](../README.md)。

## 当前文档

让其它AI接手实现时，从[后续任务包与AI交接说明](ai-development-handoff.md)进入：包含20包实施顺序、代码入口、接口约定、开发默认、逐包验收和可复制提示词。以包含二级菜单及本计划的0.5.27-dev提交为交接基线，不能只拉取上一版`3d0db66`。

本轮执行顺序见[资源、供给与建筑开发计划](economy-buildings-implementation-plan.md)：P0–P8分为基础经济、中期建筑、末期与调度三个可交付版本，含31类建筑的批次归属、依赖、接入位置和验收标准。0.5.26已移除旧地图与训练场，统一128×128开发图及5×5主脑；P1五项资源账本、供给字段与多单位目录已接入，P2新供给设施尚未实施。

最新设计见[建筑目录 V2](building-roster-v2.md)：参照《亿万僵尸》建立31类常规建筑、升级路线与6项预留终局工程。[资源与建筑 V1](resource-building-proposal-v1.md)继续负责资源、节点系统预留/调度、风能/太阳能环境采集发电、冷却和满足参考产量时的无燃料开局核算。核心方向已确认，新增规则及具体数值为提案，新经济参数尚未切换；地图与主脑占地已先行接入。

| 文档 | 负责内容 |
|---|---|
| [AI开发交接](ai-development-handoff.md) | 0.5.27提交基线、20个任务包、具体实施和验收、交接模板 |
| [本轮开发计划](economy-buildings-implementation-plan.md) | P0–P8任务、版本A/B/C、依赖、31类建筑归属与验收 |
| [建筑目录 V2](building-roster-v2.md) | 完整建筑、原作对应、造价、升级、科技前置与终局工程提案 |
| [资源与建筑 V1](resource-building-proposal-v1.md) | 新资源产线、节点容量、电/冷却供给与开局账面核算 |
| [基础设定](game-design-concept.md) | 游戏身份、三幕、胜负、体验验证 |
| [资源](resources.md) | 五项账本迁移状态、旧经济基线与新供给提案入口 |
| [建造经营](building-economy.md) | 建筑、解锁、建造/生产/维修/拆除 |
| [操作](operations.md) | 目标操作方案、快捷键与 HUD |
| [地图地形](map-terrain.md) | 地形、矿点、主口、出生与退守纵深 |
| [敌种与波次](waves-enemies.md) | 游荡敌、噪声、波次、原型机、感疫 |
| [视野迷雾](vision-fog.md) | 三态迷雾、LOS、覆盖探索与方向分级 |
| [数值](values.md) | 当前建筑/资源标尺与待调参数 |
| [代码架构](architecture.md) | 模拟/表现边界、命令、数据与规模目标 |
| [模块复用调研](reuse-research.md) | 候选来源、采用结论与验证限制 |
| [开发计划](development-plan.md) | 当前进度、同步任务、待明确规则与里程碑验收 |

## 实施与检查

[二级建造菜单](../validation/build-menu.md)记录0.5.27的六分类、31项目录、已开放/缺料/未开放区分与原生画面检查。新建筑功能仍按原计划逐批接入。

[五项资源账本与单一开发图](../validation/p1-ledger-single-map.md)记录0.5.26的删除范围、付款/退款/队列迁移、供给接口、既有检查和待验项。

[128×128开发图](../validation/development-map-128/README.md)记录新图布局、资源预留、34目标连通、预览运行时路线、原生画面及旧经济边界。

[探图与实时视野分离](../validation/exploration-sight.md) 记录 0.5.24-dev 的无阻挡地形探索、受 LOS 约束的实时可见、原生对照画面和检查边界。

[视角与 HUD](../validation/reference-view-hud.md) 记录 0.5.23-dev 对用户截图的格线比例估计、普通缩放与全图总览、底部指挥台布局、原生画面与交互待验。

[P0/P1-R 接手核对](../validation/p0-p1r-takeover.md) 记录 0.5.27-dev 基线、交易闭环静态审计、生产队列/退款修复与开发默认；不表示 P1 原生交易验收完成。

[P2a 连通供电](../validation/p2a-coverage.md) 记录主脑根覆盖 BFS、中继/冷却塔内容、覆盖 revision 与差集刷新、启动检查及原生未验项。

[P2b 环境采集](../validation/p2b-environment.md) 记录风能/太阳能评分、采集区预约、运行时环境输出、预览与探索差集刷新。

[P2c 地图环境](../validation/p2c-map-environment.md) 记录风口/水域环境层、同源地图编译与参考风能/太阳能选址实测。

[P2d 无燃料开局](../validation/p2d-opening.md) 记录新供给/配方、scout/sentinel、固定首波、启动日志与原生未验项。

[P3a 燃料与冶炼](../validation/p3a-fuel-smelter.md) 记录原生燃料矿点、燃料采集站、热能冶炼周期与首次合金实测。

[P3b 科技与升级](../validation/p3b-tech-upgrade.md) 记录科技 I/II、主脑 I→II、原址升级状态与原生未验项。

[P3c 材料维修](../validation/p3c-repair-version-a.md) 记录4HP/s、材料25%、整数余数与版本A边界。

[P4a 强化供给与水冷](../validation/p4a-supply-water.md) 记录节点II、深层矿、强化电源、水冷正交邻水与冶炼周期边界。

[P4b 闸门与陷阱](../validation/p4b-gate-traps.md) 记录闸门/电磁/爆破内容、陷阱触发与团队通行层缺口。

[P4c 中期火力与重装](../validation/p4c-midfire-heavy.md) 记录电弧范围伤害、重装工厂/单位与维修站缺口。

[P4d 瞭望与雷达](../validation/p4d-lookout-radar.md) 记录视野源、雷达预警字段与提前量缺口。

[M6 bundle 本地审查](../validation/m6-bundle-review.md) 记录本次合入的两个提交、原生导入发现的编译/接线问题、穿墙寻路修复，以及本地 43 个脚本、49 项既有回归、启动和原生画面的复验结果与限制。

[卡顿与游荡节奏调整](../validation/performance-wanderers.md) 记录 0.5.18-dev 的后台行军场、局部 A*/RVO 更新、视野记忆复用、开局禁刷与游荡移速调整，以及加速战斗性能证据和待验项。

[破口接敌场](../validation/assault-field.md) 记录当前 0.5.22-dev 的静态全局场、多区域缺口导流、顺路建筑目标、结构失效及检查边界，并保留 0.5.21 的历史方案。

[M5 实施与检查](../validation/m5-threat-defense.md) 汇总当前实现及有效检查结果，[bundle 审查记录](../validation/m5-bundle-review.md) 保留逐提交结论；待验收清单与后续顺序统一看[开发计划](development-plan.md)。

[视野迷雾实施与检查](../validation/m6-vision-fog.md) 记录 2026-11-07 接入的三态迷雾、视野与信息过滤、49 项行为检查及原生画面验证。

[单位队列与朝向](../validation/formation-movement.md) 记录方向队列、稳定落点、单位朝向和实际采用的 MIT 编队模块；[直达路径检查](../validation/movement-paths.md) 记录路径引导与交互验收边界。

[待命开火检查](../validation/idle-fire.md) 记录普通移动结束后只在射程内开火、不主动追击的规则与检查边界。

[小地图检查](../validation/minimap.md) 记录左下角小地图的读模型贴图实现、左键跳镜头、M 键全屏切换（预留区域管理载体）与输入隔离；[基座与维修检查](../validation/ruins-repair.md) 记录交战状态维修暂停（被攻击后周边 6 格内有敌军期间）、被毁留基座（施工中被毁直接移除）、无碰撞不阻挡的通行豁免、折扣重建、清除与一键修复；[精英闭环检查](../validation/elite-victory.md) 记录原型机电磁庇护（6 格内受伤减半，杀死即解除）与正常移速穿墙、对敌伤害单一结算入口、有限波次胜利判定与胜负面板。

旧设计稿和 M1–M4 实施流水已清理，仍有效的检查结果与待验项已汇总；旧版本从 Git 历史追溯。[旧原型资源](../archive/README.md) 仅保留非运行依赖的场景和素材。
