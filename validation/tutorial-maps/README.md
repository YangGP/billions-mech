# 边缘基地教程与玩法验证图

2026-11-12，Godot4.7.2。主菜单“开始游戏”后从地图下拉框选择。两关都使用原有三维战场、二维模拟/导航/HUD与迷雾，600币/80金属矿、2侦察兵开局；没有免费建筑、额外钱包、解锁或教学脚本框架。最新地图为斜向边界、正方形展示。完成度查[开发计划](../../docs/development-plan.md)。

| 关卡 | 基地与布局 | 节奏与用途 |
| --- | --- | --- |
| 西岸前哨，96×96网格/3927完整格 | 几何面积4096平方格，保持原64×64面积；主脑(14,41)，距显示左边约2.9逻辑格；岩体封三边，12格宽单隘口；4金属/3碳晶/2超导矿点 | 4:40预告、5:00首波，两波；先练采集/供给/军工，再守单隘口 |
| 双桥河谷，127×127网格/7403完整格 | 几何面积7680平方格，保持原96×80面积；主脑(113,69)，距显示右边约3.4逻辑格、靠东南角；两处6格宽陆桥；6金属/4碳晶/3超导矿点 | 2:40预告、3:00首波，四波；验证双线防御、临水选址、跨河扩张和科技链 |

布局坐标为主脑5×5占地左上格。新关卡不开放战役候选模式，清除最后一波敌军后胜利，主脑被摧毁失败；具体预算/间隔见[数值表](../../docs/values.md#2-全局时间与开局)。当前节奏是待试玩候选值。

## 源与运行数据

| 关卡 | 布局源 | 运行开局 | 三维编辑总览 |
| --- | --- | --- | --- |
| 西岸前哨 | [tutorial_coast_64.source.json](../../content/maps/tutorial_coast_64.source.json) | [tutorial_coast.tres](../../content/tutorial_coast.tres) | [tutorial_coast_overview.tscn](../../scenes/tutorial_coast_overview.tscn) |
| 双桥河谷 | [validation_river_96.source.json](../../content/maps/validation_river_96.source.json) | [validation_river.tres](../../content/validation_river.tres) | [validation_river_overview.tscn](../../scenes/validation_river_overview.tscn) |

地图`.tres`由同名`.source.json`编译。源内`session`保存出生点、教学说明与波次差异，开局Resource以`content/development_128.tres`为编译模板复用全部定义。模板目录改变后也须重新编译两关，不能只改生成Resource。根目录执行：

```powershell
python tools/compile_development_map.py --source content/maps/tutorial_coast_64.source.json --output content/maps/tutorial_coast_64.tres --qa-dir validation/tutorial-maps/coast --settings-output content/tutorial_coast.tres
python tools/compile_development_map.py --source content/maps/validation_river_96.source.json --output content/maps/validation_river_96.tres --qa-dir validation/tutorial-maps/river --settings-output content/validation_river.tres
```

两关复用原有Pillow地形栅格化、SciPy连通/Qhull与Godot原生导航，无新美术或依赖。各自[西岸报告](coast/layout-report.json)/[河谷报告](river/layout-report.json)与bundle保留源SHA256。主脑占用后均为1个可走连通区，分别17/23个锚点；所有矿点有不包含其他矿点的合法2×2采矿位置，建设参考位与入口可达，水域与风口不重叠。四隘盆地同样重新编译，184×184包围网格、16042完整格、几何面积16384平方格、34个锚点。

## 正方形展示与限制

边界沿逻辑格对角方向，按现有3:4纵向压缩投影后成为正方形。源中`original_dimensions`/`target_playable_area`保存原矩形面积，`dimensions`扩大为包围网格，分数顶点存于`playable_polygon`。编译器用SciPy ConvexHull.volume验证总面积分别16384/4096/7680平方格，原生检查也以浮点容差复核；没有缩放建筑、单位、格子或画面。完整可玩格数少于几何面积的部分是显示边缘半格，另行统计，不声称完整格数也完全相同。

编译器用现有SciPy/Qhull半平面保留分数边界精度，对四个格角作判定；清除外部水域/风口，将外部格设为阻挡，运行时沿用MechMapDefinition/MechGridState。Camera3D使用投影边界夹持平移，视野大于地图的轴固定居中，Home适配实际轮廓；F1保证边缘主脑可见，代替此前的强制居中。地面半格经原生Geometry2D裁剪，只作平直边缘显示。布局、矿点、开局单位已同步平移，波次、资源总量及主脑参数不变。默认源内`settings_output`使不带参数的编译命令也同步生成默认开局Resource。

## 实际检查与画面

既有[验证入口](../vision_checks.gd)现为143项，覆盖选择传递、出生位置、快照尺寸、基地距真实边界、初始节点/金属矿/太阳能合法预览、出生安全距离和重开。新增三图等面积、2D/3D方形投影、编译与原生完整格掩码一致性、半格拒建、越界建造不扣款/移动拒绝、50%/70%/200%四方向镜头夹持及Home适配。旧边缘基地“强制居中”检查更新为可见，以符合本轮限制镜头要求，未删除原用例。

```powershell
godot --headless --path . --script res://validation/vision_checks.gd -- --level-smoke
godot --path . --resolution 1920x1080 --script res://validation/vision_checks.gd -- --capture-menu
```

`--level-smoke`让每张新图在重开后运行600引擎帧，共145项通过；`--capture-menu`保存菜单/开局/等面积正方形总览，含10次截图写入检查共153项通过。两图还在1280×720窗口出图检查布局。没有新建测试脚本，也没有删除原用例。

- 西岸：[任务选择](../screens/level-select-coast.png)、[正常迷雾开局](../screens/coast-start.png)、[独立三维总览](../screens/coast-overview.png)。
- 河谷：[任务选择](../screens/level-select-river.png)、[正常迷雾开局](../screens/river-start.png)、[独立三维总览](../screens/river-overview.png)。

总览使用已有地图编辑预览显示全图，不改变正常游戏的探索状态。运行日志中根证书、Steam外部编辑器设置保存和GLES `_save_to_cache`失败属于环境问题，未发现SCRIPT/Parse/Compile错误。真实输入工具此前返回native pipe unavailable；未完成鼠标/键盘/手柄操作、自然经济科技链、完整两波/四波和规模性能验收，不能用连通、截图或短时启动代替。
