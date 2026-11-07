# 小地图实施与检查

更新：2026-11-07，0.5.13-dev。基础包与全屏切换已接入；本机 Godot 不可用，全部原生检查未执行，鼠标键盘手感未验收。

## 接入内容

- `presentation/minimap_view.gd`（MechMinimapView extends Control）：复用 fog_view 读模型贴图模式——地形三色（开阔/崎岖/岩体，playable 外深底）与三态迷雾各一张逻辑格 ImageTexture，经投影轮廓多边形 + UV 贴图；两纹理共用同一 polygon/uvs 保证逐格对齐。地形纹理按 dimensions/terrain 字节判变，迷雾按 vision.revision + generation 判变。
- 点阵与图标按快照绘制：矿点（迷雾之下，灰区自动变暗；耗竭不画）、己方建筑浅灰占地多边形（直接用合并快照的 origin/footprint）、敌我单位圆点（敌人含 prototype 加大；训练场 practice_target 落入红点）、主脑青色常亮图标（数据取地图定义，不依赖实体存活，战败后仍显示）、镜头视野白框（与地图边界求交后再画，全景低缩放不溢出）。
- 左键点击/拖动跳镜头：控件本地坐标经 letterbox 逆变换钳制到地图边界后换算为投影世界坐标，信号经 map_hud 转发至 main.gd 调用相机 `focus_world`；不触碰建造放置/墙线/覆盖（保持放置模式，operations.md §3.2）。
- 相机接口：`map_camera.gd` 新增 `visible_world_rect()`（与 `_clamp_position` 同一半视口公式）与 `focus_world()`（打断中键拖拽并钳制）；main.gd 每帧 `present_camera`，矩形近似相等时跳过重绘。
- 全屏切换：M 键或 Minimap 面板"全屏 [M]"按钮在小尺寸（左下 240×240，Toolbar 上方无重叠）与居中 750×750 间切换；面板作为 Root 首子节点绘制在最底层，全屏时 Header/Inspector/Toolbar/反馈/失败面板浮于其上保持可读可点。Esc 优先退出全屏（设置页 Esc 在上游拦截不受影响）；全屏时进行中的框选拖拽保留，第二次 Esc 才取消。
- 输入隔离：Minimap 面板加入 HUD `_panels`（blocks_point 联动光标预览/框选/墙线落点取消），View 为 mouse_filter=STOP + clip_contents，小地图上不触发框选/下令/相机滚轮缩放，悬停时边缘滚屏自动禁用；设置页全屏遮罩打开时小地图无输入。
- 架构预留（区域管理载体）：坐标换算全部基于当前控件尺寸（NOTIFICATION_RESIZED 重算 letterbox 拟合）；`_draw` 在迷雾与实体点阵之间预留区域叠加层绘制位；面板顶部 40px 工具条（标题 + 全屏按钮）为将来区域管理操作条留位。
- 复用结论：Razoric480/godot-minimap-demo（MIT，Godot 3 代理克隆方案）已克隆到 `reference/godot-minimap-demo/` 通读分析，因每实体常驻节点/子世界重渲染与无头 sim、快照读模型和千级目标冲突而不采用；实际复用引擎原生 Control._draw/Image/ImageTexture/draw_polygon 与项目既有 fog_view 贴图模式，无新增 vendor。见[复用调研 §19](../docs/reuse-research.md)。

## 检查证据

本机（Windows）搜索 C/D 盘未找到 Godot 可执行文件，用户确认暂不可用。按 AGENT.md 未执行原生检查，仅做静态逻辑校验：

| 检查 | 结果 |
|---|---|
| 信号链 | view `focus_requested.emit` → hud `minimap_focus_requested.emit` → main `_focus_minimap`（只调 `focus_world`，不触碰 `_build_id`/墙线/覆盖），三段 grep 核对一致 |
| 坐标数学 | `_w2l`/`_local_to_world` 互逆且钳制到 bounds；`_uvs` 与 fog_view.gd 同式（轮廓点/尺寸）；`visible_world_rect` 与 `_clamp_position` 半视口公式一致；first_outpost 投影 bounds=[-1280,1280]×[768,3328] 为正方形，letterbox 拟合成立 |
| 场景完整性 | map_hud.tscn load_steps=7、ext_resource id 唯一；Minimap 为 Root 首子节点；View 四边全锚、clip_contents、mouse_filter=STOP；Toolbar 及其余节点零改动 |
| API 一致性 | present_camera/visible_world_rect/focus_world/toggle_minimap_fullscreen/set_minimap_fullscreen/is_minimap_fullscreen 两侧签名匹配；KEY_M 无既有占用；`_panels` 含 Minimap |
| 只读红线 | minimap_view 无 sim 写入、无命令提交；`_state` 引用只读遍历 |
| 空态守卫 | present_state 先于 present_map 到达时 `_polygon.size() < 3`/`_terrain_texture == null` 早退；letterbox 区点击钳制 |

**未执行（待有 Godot 后补验）**：`--import` 导入（含 minimap_view.gd.uid 生成）、4 个改动脚本 `--check-only` 语法、`validation/vision_checks.gd` 既有 49 项回归、标准/训练场 `--headless --fixed-fps 30 --quit-after 600` 启动、原生渲染画面检查。

## 验收边界

- 首版不含波次方向箭头、供电覆盖着色、右键小地图下令与小地图缩放；雷达扇形仍留待雷达批次。
- 迷雾/地形纹理为逻辑格粒度（128×128 像素级），非逐像素平滑边缘；点阵每发布帧重绘，千级单位若成瓶颈可改批量点绘制（未实现）。
- 全屏态模拟不暂停、仅导航；Esc 全屏优先级副作用：全屏时进行中的框选拖拽保留至第二次 Esc。
- 人工待验：三色地形/三态迷雾/点位/矿点/主脑常亮/视野框随缩放与全景变化；点击与拖动跳镜头（含 letterbox 钳制手感）；建造模式下跳镜头不退出放置；M/按钮切换、Esc 优先退全屏；设置页打开时小地图无输入；战败后仍可跳镜头。
