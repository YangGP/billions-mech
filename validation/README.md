# 验证记录索引

当前版本 **0.5.90-dev**，默认三维入口已启用。完成度只维护于[开发计划](../docs/development-plan.md)，人工结果只更新[三维人工清单](3d-manual-checklist.md)。

## 当前有效材料

| 材料 | 用途与边界 |
| --- | --- |
| [三维人工清单](3d-manual-checklist.md) | 当前人工待验与已确认范围；本清单是验收入口 |
| [三维交互与性能](3d-interaction-performance.md) | 当前三维求交、墙连接、真实敌军压力与性能结论 |
| [三维测量 JSON](3d-interaction-performance-checks.json) | 同种子 CPU 样本、实际/可见数量、暂停/胜败状态 |
| [128×128 地图材料](development-map-128/README.md) | 布局、地图编译、导航和预览来源 |
| [视野回归脚本](vision_checks.gd) | 既有 49 项检查入口；不新增测试脚本 |
| [最新三维画面](screens/3d-interaction-walls.png) | 主脑、侦察机、墙线施工与 HUD；画面证据，不代表整局通过 |

## 检查方式

```powershell
godot --headless --path . --import --log-file .godot/import.log
godot --headless --path . --script res://validation/vision_checks.gd --log-file .godot/vision.log
godot --headless --path . --quit-after 600 --log-file .godot/startup.log
```

解析检查需按实际枚举覆盖所有活动脚本；查看退出码之外还须扫描 `SCRIPT ERROR`、解析及编译错误。原生交互和正式波次须另有实际操作证据。

## 清理规则

- 阶段性实现记录、历史审核、旧 2D 专题和一次性截图已清理。
- 需要追溯时从 Git 历史查询，不把旧记录当作当前验收。
- 文档清理不改变待验状态，也不重跑或新增测试。
