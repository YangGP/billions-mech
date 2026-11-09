# 三维表现首批接入记录

2026-11-10。实施前基线提交为`42972f8`，包含上一轮建造光标、瞬间拆除、建筑视野、跨UI框选修复和迁移计划。本记录仅覆盖三维开发入口首批接入，阶段完成度查[开发计划](../docs/development-plan.md)。

后续已接入完整工程模型目录和战场提示，Godot项目与bat均默认启动3D；用户暂缓3D肖像。以下“通用兜底/待替换/2D默认入口”等描述仅代表首批接入时状态，最新证据与27–34复验项查[后续记录](3d-content-and-overlay.md)。

## 接入内容

- `scenes/main_3d.tscn`以Node3D组织地面、模型、正交Camera3D和光照；复用现有HUD、模拟、命令、配置和敌人系统。`main.gd`改为Node组合根，2D对照入口仍可运行。
- 相机统一提供逻辑地图↔屏幕、镜头地面范围、焦点、总览和缩放接口；三维路径直接调用Camera3D/Plane，点选直接调用AABB求交，不依赖3D导航或单位物理体。
- 地形使用16×16分块静态网格，原生Geometry2D负责地图轮廓裁剪/三角化；模型使用共享BoxMesh/CylinderMesh与按种类/空间块组织的MultiMesh，无逐单位逻辑节点。
- 主脑、侦察机已有三维占位形状，其它内容使用通用模型兜底；快照驱动位置、朝向、施工高度、基座和断供颜色，实体ID与实例槽位分离。完整兵种/建筑差异、升级外观、能力提示和战斗特效尚待第二阶段。
- 已接入三维建造格/占地/立体框预览、墙线、选中标记、目标标记；命令仍由原权威入口校验。小地图输出逻辑位置并绘制镜头地面多边形，HUD肖像仍用旧2D白模，后续替换。
- 三态视野纹理由原vision_system提供，按模型/地面的世界XZ采样；未知片元discard，避免受光照后露出地图边界。首轮关闭模型投影阴影；敌军只取玩家过滤快照。已捕捉到未知地面受光显轮廓问题并修正，不能据此宣称所有高模型/特效场景均已验收。

## 启动

```powershell
.\run.bat
.\run.bat -- --campaign
.\run.bat -- --overview
```

也可在Godot中运行`scenes/main_3d.tscn`。`run.bat`及Godot项目均已默认打开3D场景。完整迁移和交互复验继续进行，当前不能当作最终3D版本交付。

入口调整已用`.\run.bat --headless --quit-after 30`检查，退出码0，运行日志确认`3D development whitebox`，未发现脚本错误。

## 已执行检查

| 检查 | 结果与边界 |
| --- | --- |
| 提交前基线导入、既有视野回归、普通启动600帧 | 无脚本错误，49项0失败；日志`.godot/pre-3d-{import,vision,normal}.log` |
| 迁移后Godot导入、52个活动脚本逐一check-only | 无解析/编译错误；枚举commands/content/presentation/sim，未新增测试脚本 |
| 既有`validation/vision_checks.gd` | 49项0失败；`.godot/migration-vision.log`；不覆盖3D投影和真实鼠标输入 |
| 2D普通启动600帧 | 无脚本错误；`.godot/migration-2d-normal-final.log`，2D对照截图复核通过 |
| 3D普通/战役各600帧 | 无脚本错误；`.godot/migration-3d-normal-final.log`、`migration-3d-campaign.log`；只是短时启动 |
| 3D既有压力入口1800帧、固定60FPS | 无脚本错误，诊断轮换包含9种敌人；`.godot/migration-3d-stress.log`；约30秒模拟，不代表目标规模/整局或GPU性能通过 |
| 实际OpenGL渲染与截图 | RTX 4080 SUPER，Godot 4.7.2/Compatibility；1920×1080常规与总览均能出图；另以1280×720窗口请求启动，导出仍是项目1920×1080逻辑画布，不当作全部尺寸验收 |
| 实际GPU普通启动600帧 | `.godot/migration-3d-gpu-startup.log`；开局记录draw calls=129、视图CPU均值约0.37ms；未测目标战斗密度、GPU单独耗时或显存，不据此验收规模性能 |

[三维首批画面](screens/migration-3d-first-pass.png)与[适配后2D对照](screens/migration-2d-reference.png)通过Godot原生Movie Maker逐帧导出并人工查看，没有模拟UI操作。图中模型仍是工程占位，不是正式美术。

原生渲染日志保留`.godot/migration-3d-render-checked.log`及`migration-3d-overview-final.log`。引擎存在根证书读取、Steam安装目录编辑器设置写入提示；三维实际渲染还出现`drivers/gles3/shader_gles3.cpp:_save_to_cache`的`f.is_null()`缓存保存提示，但图像成功导出，未发现着色器编译错误。不能将其写为“日志完全无错误”。

Computer Use已按技能初始化并尝试列举应用，返回`Computer Use native pipe is unavailable ... os error 2`，因此没有执行真实鼠标/键盘交互。不将源码接线、启动、截图或旧2D人工结果当作3D输入通过。

## 首批人工复验清单

以下均为待验，沿用[迁移方案](../docs/3d-presentation-migration.md)，后续发现问题直接修复：

1. 开局主脑和两名侦察机正常显示；中键/方向键/边缘平移、滚轮、F1回主脑、Home总览可用，缩放时鼠标下地面位置稳定。
2. 点击算力节点后首个预览跟随鼠标，放置落点与预览一致；再试1×1墙与2×2太阳能，确认占地边缘和格子对齐，非法位置不扣款。
3. 建造方向键微调不平移镜头，Enter正确下单；移动鼠标恢复跟随，连续放置、取消和Shift墙线仍工作。
4. 单击模型可选中；框选单位优先，Shift追加/Ctrl切换、双击同类和编队召回正确；建筑后方友军可框选，模型重叠点选遵循深度。
5. 框选拖入建造菜单/小地图松开，框线裁剪且选择成功，不点击UI；失焦/离窗、设置和弹窗不残留手势。
6. 侦察机右键移动、A攻击移动、工厂集结点落在指示格；小地图点击/拖动、全屏切换、区域框选与镜头范围同步。
7. 暂停下单不推进施工，恢复后正常；取消施工和瞬间拆除/清基座退款、占地与视野一致；重开恢复初始状态，没有旧模型。
8. 探索/灰雾/实时视野切换正确，普通完工连通建筑保持4格视野；未知地面不露地图边界，隐藏敌人不可被点击或看见模型。

完成这些不等于阶段2–5完成：完整模型目录、全部范围/能力提示、肖像、编辑器预览、全生命周期、1–2k敌军与最终入口收口仍须继续实现和验证。
