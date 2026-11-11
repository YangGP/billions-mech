# 验证记录索引

当前版本 **0.5.90-dev**，默认从主菜单选择任务后进入三维战场。完成度只维护于[开发计划](../docs/development-plan.md)，人工结果只更新[三维人工清单](3d-manual-checklist.md)。

## 当前有效材料

| 材料 | 用途与边界 |
| --- | --- |
| [三维人工清单](3d-manual-checklist.md) | 当前人工待验与已确认范围；本清单是验收入口 |
| [三维交互与性能](3d-interaction-performance.md) | 当前三维求交、墙连接、真实敌军压力与性能结论 |
| [三维测量 JSON](3d-interaction-performance-checks.json) | 同种子 CPU 样本、实际/可见数量、暂停/胜败状态 |
| [开发地图材料](development-map-128/README.md) | 原128×128面积开发图，现用184×184包围网格；含布局、地图编译和历史来源 |
| [既有回归脚本](vision_checks.gd) | 保留原49项，菜单/会话/新关卡/等面积正方形边界检查共143项；没有新增测试脚本 |
| [边缘基地新关卡](tutorial-maps/README.md) | 两张地图源、编译材料、教学目标和原生总览；完整难度仍待试玩 |
| [主菜单画面](screens/main-menu.png)、[标准任务](screens/level-select-standard.png)、[战役任务](screens/level-select-campaign.png) | Godot实际渲染；画面证据，不代表真实点击或完整单局通过 |
| [最新三维画面](screens/3d-interaction-walls.png) | 主脑、侦察机、墙线施工与 HUD；画面证据，不代表整局通过 |

## 检查方式

```powershell
godot --headless --path . --import --log-file .godot/import.log
godot --headless --path . --script res://validation/vision_checks.gd --log-file .godot/vision.log
godot --headless --path . --quit-after 600 --log-file .godot/startup.log
```

解析检查需按实际枚举覆盖所有活动脚本；查看退出码之外还须扫描 `SCRIPT ERROR`、解析及编译错误。原生交互和正式波次须另有实际操作证据。

## 主菜单与关卡选择（2026-11-11）

主菜单最初接入时，Godot4.7.2下导入及变更脚本解析无SCRIPT/Parse/Compile错误，既有回归82项通过。覆盖按钮信号接线、标准→战役→标准切换、不修改共享配置、重开保留模式和归零计时、返回确认的运行/已暂停/战败恢复语义、离场释放旧实体。2026-11-12在两张新关卡和等面积正方形展示基础上，常规检查143项、两图各600帧检查145项、原生渲染含截图写入检查153项；详见[新关卡记录](tutorial-maps/README.md)。截图生成命令：

```powershell
godot --path . --resolution 1920x1080 --script res://validation/vision_checks.gd -- --capture-menu
```

1920×1080与1280×720渲染布局已出图检查；1280×960窗口沿用项目等比策略，实际内容为1280×720，其余留黑边。菜单、标准战场及战役命令行入口各短时启动600引擎帧。根证书读取和外部Steam编辑器设置保存提示属于环境错误，日志须与脚本错误分开判断。Windows Computer Use两次返回native pipe unavailable，未完成真实鼠标/键盘及手柄验收；程序化信号调用和原生截图不能代替真实输入。未进行完整四波/战役或规模性能验收。

## 清理规则

- 阶段性实现记录、历史审核、旧 2D 专题和一次性截图已清理。
- 需要追溯时从 Git 历史查询，不把旧记录当作当前验收。
- 文档清理不改变待验状态，也不重跑或新增测试。
