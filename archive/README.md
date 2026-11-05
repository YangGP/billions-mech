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

## 旧原型资源

`legacy-prototype/` 保留旧场景、数据、图像、字体资源和导入缓存。按用户此前指示，旧脚本源码及 UID 已删除。

`archive/.gdignore` 阻止 Godot 扫描归档。新入口为项目根目录的 `project.godot` 与 `scenes/main.tscn`。旧场景仍引用已删除脚本，不能作为新工程运行。
