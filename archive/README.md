# 历史资料归档

当前设计从 [文档索引](../docs/README.md) 进入。本目录保留已被替代的资料，不作为新工程的规则、数值或运行依赖。

## 旧设计与开发文档

2026-11-05 清理时移入 `design-history/`，保留历史内容供追溯：

| 文档 | 归档原因 | 当前入口 |
|---|---|---|
| [项目设计文档 v0.2](design-history/区域指挥型生存RTS_设计文档_v0.2.md) | 旧经济建设/区块视图原型，已被分系统专稿替代 | [基础设定](../docs/game-design-concept.md) |
| [基础开发指南 v0.1](design-history/区域指挥生存RTS_基础开发指南_v0.1.md) | 旧目录、节点和原型 M1/M2 已失效 | [代码架构](../docs/architecture.md)、[开发计划](../docs/development-plan.md) |
| [首切片规格 v0.3](design-history/slice-spec-v0.3.md) | 单币经济、旧建筑/敌人数值、短波次和雷达数量/构成预告已过时；保留 M3 参数依据 | [数值](../docs/values.md)、[波次](../docs/waves-enemies.md)、[开发计划](../docs/development-plan.md) |
| [开发计划 v0.4](design-history/development-plan-v0.4.md) | 尚未包含采矿、游荡敌/噪声/感疫与提前的视野工作 | [当前开发计划](../docs/development-plan.md) |

## v0.5 并行设计草稿（design / implementation）

2026-11-06 整理时移入 `design-drafts/`。这套草稿是 11/05 下午一次"设计/实现分目录"重组尝试的产物，基于两条未采纳的前提：

- **vendor 框架基座**（implementation/architecture.md：单资源、无采矿、M0–M7 从零规划）——与 11/04 重启记录"未导入 vendor"及现行原生实现（AStarGrid2D + NavigationServer2D/RVO）冲突；
- **10min 波间隔、每幕 4 波**——已于 2026-11-06 经 TAB 对照**回采为现行口径**（[数值稿](../docs/values.md) §2/§12：25/40/64/102，W3 首精英）；威胁侧推导（§9–§13）随之整体生效。

其中 [values.md 草稿](design-drafts/design/values.md) 的威胁侧推导（§9–§13：TAB 基线换算、敌种表、波次预算曲线、半径族、感疫换算）是全套草稿中唯一未进入现行稿的内容，曾作为 M5 前补齐敌种/预算曲线参数的参考底稿——随着 10min/4 波口径被回采（见上），其威胁侧推导已整体进入现行[数值稿](../docs/values.md) §11–§15。其余文件与现行 docs/ 平铺稿重复或已被实现事实替代：施工进度/血量分立、矿点锚格绑定、超载恢复例外、生产队列细则、操作与架构均以现行稿为准。

## 旧原型资源

`legacy-prototype/` 保留旧场景、数据、图像、字体资源和导入缓存。按用户此前指示，旧脚本源码及 UID 已删除。

`archive/.gdignore` 阻止 Godot 扫描归档。新入口为项目根目录的 `project.godot` 与 `scenes/main.tscn`。旧场景仍引用已删除脚本，不能作为新工程运行。
