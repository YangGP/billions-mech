# 验证记录索引

当前功能基线为 **0.5.89-dev / `4f8218b`**。完成度和待开发事项只维护于[开发计划](../docs/development-plan.md)，本目录保存验证证据及其适用边界。

## 当前证据

| 材料 | 用途与边界 |
| --- | --- |
| [0.5.89 审核与修复](review-fixes-0.5.89.md) | 最近修复、48 脚本检查、49 项既有回归、启动/压力/原生画面；逐项交互和完整终波仍未验 |
| [机器可读摘要](review-fixes-0.5.89-checks.json) | 当次检查的帧数、环境及日志路径；提交状态字段是记录生成时的快照 |
| [原生 HUD](screens/review-0.5.89-hud.png) | 修复后画面布局证据，不是输入或整局验收 |
| [既有视野回归](vision_checks.gd) | 现有 49 项检查入口；遵守仓库约定，不追加新测试脚本 |
| [128×128 地图材料](development-map-128/README.md) | 布局、地图编译、导航和预览来源；区分生成时配置与当前运行配置 |

## 保留的历史技术专题

下列记录有独有的实现说明、来源或测量，保留为历史证据。文中“当前”仅指记录写成时的版本，不能替代现行规则、数值或验收。

| 专题 | 内容 |
| --- | --- |
| [局部行军场](assault-field.md) | 多区域、破口优先、顺路建筑目标与拓扑失效 |
| [性能与游荡节奏](performance-wanderers.md) | 掉帧定位、后台计算、版本间测量条件及局限 |
| [直达路径](movement-paths.md)、[方向队列](formation-movement.md)、[待命开火](idle-fire.md) | 路点、复用模块与单位规则来源 |
| [三态视野](m6-vision-fog.md)、[探图分离](exploration-sight.md) | 既有回归来源、无阻挡探索及实时 LOS |
| [参考视角与 HUD](reference-view-hud.md)、[小地图](minimap.md) | 投影与视图接线、原生画面及当时的输入边界 |
| [基座与维修](ruins-repair.md)、[原型机与胜负](elite-victory.md) | 生命周期和首个精英闭环的历史依据；旧维修费用/供给口径已被现行系统稿替代 |

## 检查方式

Godot 在 PATH 中时，可在项目根目录执行：

```powershell
godot --headless --path . --import
godot --headless --path . --script res://validation/vision_checks.gd
godot --headless --path . --script res://sim/sim_core.gd --check-only
godot --headless --path . --quit-after 600
godot --headless --path . --quit-after 900 -- --stress --perf
```

解析检查需要按实际枚举覆盖所有活动脚本；示例中的单文件命令不是全量检查。查看退出码之外还须扫描 `SCRIPT ERROR`、解析及编译错误。环境证书/外部编辑器配置写入提示单独记录，不掩盖项目错误。原生交互和正式波次须另有实际操作证据。

## 清理规则

2026-11-09 文档整理：P0–P8 的一次性实施流水、旧 bundle 合入记录、0.5.88 交付/计划快照和重复总计划已由当前开发计划、系统规则及 0.5.89 修复记录接替，不再保留第二套完成度表。代码、地图生成数据、许可证、既有测试和独有性能证据不在清理范围。本次删除28份被替代的文档及12张无引用的旧截图；旧文档和图片完整内容可从整理前提交 `4f8218b` 查询。


本次整理检查：32份保留Markdown中257个本地链接/锚点均有效，31行基础建筑及22条升级链与配置对应，`git diff --check`通过。仅改文档及过期截图，没有改代码、Resource、地图数据或既有测试，也没有重新执行游戏验收。
