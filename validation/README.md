# 验证记录索引

当前版本为 **0.5.89-dev**，运行代码基线为`b3ed91e`，默认三维入口已启用。完成度只维护于[开发计划](../docs/development-plan.md)，人工结果只更新[三维人工清单](3d-manual-checklist.md)，本目录其余报告保存各次验证证据。

## 当前证据

| 材料 | 用途与边界 |
| --- | --- |
| [三维交互与性能记录](3d-interaction-performance.md) | 58脚本/49项回归、模型原生求交、墙连接修正、实际渲染、1000/2000真实敌军短时测量；2000模拟预算及综合性能未通过 |
| [三维测量JSON](3d-interaction-performance-checks.json) | 同种子CPU样本、实际数量、可见数量、暂停/胜败状态及测量阶段；不作为真实FPS证据 |
| [三维人工清单](3d-manual-checklist.md) | 基础1–8及27–38，共20项待验；保留3D肖像暂缓约定 |
| [最新三维画面](screens/3d-interaction-walls.png) | 主脑、侦察机、墙线施工与HUD；画面证据，不代表鼠标/键盘或整局通过 |
| [拆除/视野/跨UI框选修正](demolition-vision-selection.md) | 用户9通过、11旧拆除成功；10改瞬间拆除，补普通建筑视野并修复跨UI框选；新行为待复验 |
| [建造与选择人工验证](build-selection-manual.md) | 用户确认8/8通过：首次/连续放置、切换与快捷键、鼠标/键盘切换、HUD取消、暂停与非法位置、框选和双击侦察机；不覆盖新敌人或完整生命周期 |
| [既有视野回归](vision_checks.gd) | 现有 49 项检查入口；遵守仓库约定，不追加新测试脚本 |
| [128×128 地图材料](development-map-128/README.md) | 布局、地图编译、导航和预览来源；区分生成时配置与当前运行配置 |

## 保留的历史技术专题

下列记录有独有的实现说明、来源或测量，保留为历史证据。文中“当前”仅指记录写成时的版本，不能替代现行规则、数值或验收。

| 专题 | 内容 |
| --- | --- |
| [三维首批接入](3d-presentation-first-pass.md) | `f6ae023`阶段的坐标/相机/迷雾、52脚本和2D/3D对照；早期兜底模型已被完整目录替代 |
| [三维模型与战场提示](3d-content-and-overlay.md) | `117c623`阶段的66项模型、地图预览和2000几何实例截图；56脚本是当次枚举口径，当前含vendor为58 |
| [新敌人接入](enemy-integration.md) | 阵容/旧原型机清理、机制适配、加速首波及当次检查；不当作当前三维输入验收 |
| [0.5.89审核](review-fixes-0.5.89.md)、[摘要](review-fixes-0.5.89-checks.json)、[2D HUD](screens/review-0.5.89-hud.png) | 三维迁移前的生命周期修复、测量与画面；48脚本和提交状态仅指记录生成时 |
| [局部行军场](assault-field.md) | 多区域、破口优先、顺路建筑目标与拓扑失效 |
| [性能与游荡节奏](performance-wanderers.md) | 掉帧定位、后台计算、版本间测量条件及局限 |
| [直达路径](movement-paths.md)、[方向队列](formation-movement.md)、[待命开火](idle-fire.md) | 路点、复用模块与单位规则来源 |
| [三态视野](m6-vision-fog.md)、[探图分离](exploration-sight.md) | 既有回归来源、无阻挡探索及实时 LOS |
| [参考视角与 HUD](reference-view-hud.md)、[小地图](minimap.md) | 投影与视图接线、原生画面及当时的输入边界 |
| [基座与维修](ruins-repair.md)、[原型机与胜负](elite-victory.md) | 生命周期和首个精英闭环的历史依据；旧维修费用/供给口径已被现行系统稿替代 |

## 检查方式

Godot 在 PATH 中时，可在项目根目录执行：

```powershell
godot --headless --path . --import --log-file .godot/import.log
godot --headless --path . --script res://validation/vision_checks.gd --log-file .godot/vision.log
godot --headless --path . --script res://sim/sim_core.gd --check-only --log-file .godot/parse.log
godot --headless --path . --quit-after 600 --log-file .godot/startup.log
godot --headless --path . --quit-after 600 --fixed-fps 60 --log-file .godot/stress-2000.log -- --stress --stress-enemies=2000 --perf
```

解析检查需要按实际枚举覆盖所有活动脚本；示例中的单文件命令不是全量检查。查看退出码之外还须扫描 `SCRIPT ERROR`、解析及编译错误。环境证书/外部编辑器配置写入提示单独记录，不掩盖项目错误。原生交互和正式波次须另有实际操作证据。

## 清理规则

2026-11-09已清理被替代的实施流水、0.5.88快照、重复计划及无引用截图；整理前内容可从`4f8218b`查询。2026-11-10合并三维人工清单，删除重复的`bundle-review-c220110.md`，修正当前入口/交接说明并分开当前与历史证据。原bundle已不在工作区；其引入为`fe07dc4`→`c220110`快进，曾验证依赖和完整性，后续双击坐标/升级族修复已保存于迁移前基线。详细原报告可用`git show b3ed91e:validation/bundle-review-c220110.md`查看。

来源/许可证、用户原始设计、地图生成数据、既有测试和独有测量证据继续保留。文档整理不改变任何人工待验状态，也不重跑或新增游戏测试。

本次整理核对42份Markdown，391个本地链接（含6个锚点）均有效，`git diff --check`通过；仅修改文档，未重新执行游戏验收。
