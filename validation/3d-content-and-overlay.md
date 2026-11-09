# 三维模型目录与战场提示接入记录

历史记录，2026-11-10，模型/入口接入提交`117c623`，接续`f6ae023`。保留66项模型、战场提示与几何批量出图证据；当前拾取/性能实测查[最新验证](3d-interaction-performance.md)，人工结果查[统一清单](3d-manual-checklist.md)，进度查[开发计划](../docs/development-plan.md)。用户暂缓3D肖像，保留2D面板肖像。

## 实际改动

- `MechModelCatalog3D`覆盖53个建筑定义（含等级/升级）、4类玩家单位、9种敌人；轮廓、配色、等级条、武器/天线/长腿/履带等用于区分身份。施工缩放高度、断供变暗、被毁显示基座。全部为工程模型，不是正式美术和动画，也没有新增部件破坏机制。
- 直接复用BoxMesh/CylinderMesh/SphereMesh等原生几何体，使用原生SurfaceTool.append_from/index合并每种模型；按模型和空间块复用MultiMesh。原来每个模型部件分别绘制的方式已替换；实例槽位不承担实体ID语义。
- `MechBattleOverlay3D`集中绘制选中/受伤/敌军血条、施工/升级/生产进度、断供/驻军/维修、冲锋/保护/拾荒/干扰/提速提示。使用真实模型包围盒定位，按HUD屏蔽区域避让；总览隐藏未选中满血对象的次要提示，不创建逐实体Label/ProgressBar。
- 建造已有完整模型的半透明预览、占地/高度框、采集区及冲突标记、攻击/覆盖/维修/光环范围；选中单位显示路径，工厂显示集结点。预览和实际下单仍走原规则校验。
- 战场接入射击线、范围命中圈、偏转场/受保护标记、冲锋/提速圈、拾荒层数圈及干扰连线；仅消费可见快照及不可变图纸。未知片元、隐藏敌军的模型/拾取及来源失效仍由原边界处理，不改伤害或导航。
- 地形添加分块批量岩体、已探索地标、按矿种区分的矿点；静态地形不因普通视野更新重建。镜头焦点、边界和小地图范围改用HUD实际可用战场矩形，选择手势仍按实际面板逐点裁剪。
- `project.godot`与`run.bat`均默认启动`main_3d.tscn`；`development_map_overview.tscn`为独立三维地图编辑预览，读取同一地图数据，不运行模拟或修改正常游戏迷雾。旧2D场景仅留对照；2D肖像及小地图依赖保留。
- 新增模型目录场景，可按建筑/玩家/敌人分类查看，并提供实例批量预览。它是内容工具，不能代替真实战斗或交互验收。

## 复用与检查

来源和边界见[复用调研](../docs/reuse-research.md)第29节。没有新写测试脚本，也没有修改模拟、账本、战斗/视野/寻路规则或内容数值。

| 检查 | 实际结果 |
| --- | --- |
| Godot导入与脚本解析 | 56个活动脚本逐一check-only无解析/编译错误；后续增量按受影响文件复查 |
| 既有视野回归 | 49项0失败；`.godot/3d-content-vision.log` |
| 默认3D普通/战役各600帧 | 无脚本错误；`.godot/3d-content-final-normal.log`、`3d-content-final-campaign.log` |
| 既有压力1800帧、固定60FPS | 无脚本错误，包含9种诊断敌人；`.godot/3d-content-stress.log`，不代表完整整局或目标密度 |
| 模型目录 | 实际加载66项，其中建筑53项；未发现Missing 3D binding警告；`.godot/3d-model-gallery.log` |
| 三维开发图预览 | 可运行/渲染；`.godot/3d-map-overview.log`、`3d-map-final-render.log` |
| 实际渲染 | RTX 4080 SUPER、Godot4.7.2/Compatibility、1920×1080；主画面、全部模型、9敌种、全图和2000模型批量均已导出查看 |
| 2000模型批量 | 9种敌人模型循环组成190个空间批次，可出图；`.godot/3d-model-load-capture.log`。仅几何，无模拟/迷雾/战斗HUD；Movie Maker固定时间步与截图开销不能用于推断真实FPS，短时非录制运行也不报告稳定FPS结论 |

截图：[战场](screens/3d-content-world.png)、[模型目录](screens/3d-content-models.png)、[敌人](screens/3d-content-enemies.png)、[地图总览](screens/3d-content-map.png)、[2000模型](screens/3d-content-2000-models.png)。截图是画面证据，不能证明鼠标下单、攻击和退款已通过。

环境仍出现根证书、Steam编辑器设置与GLES着色器缓存保存提示；图像成功输出，未发现项目脚本或着色器编译错误。再次尝试Computer Use列举应用仍返回`native pipe is unavailable ... os error 2`，没有真实输入验收结果。

## 本轮待人工复验

待验项目已统一至[三维人工验证清单](3d-manual-checklist.md)，保留原编号。本报告保存当次改动与证据；后续确认仅更新统一清单。
