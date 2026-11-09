# bundle 引入与检查：c220110

检查日期：2026-11-09。结论：bundle 完整且已成功引入；审查发现的两处功能缺陷已在工作区修复，引擎检查及既有回归通过。原生鼠标交互验收受工具环境限制，尚未完成。

## 修复结果

- 双击选择单位：复用既有 `MechIsoGeometry.project()` 将逻辑格坐标转换到镜头使用的等距投影坐标；被双击的单位始终纳入扩选起点，避免单位图形位于屏幕边缘而其脚点在矩形外时丢失选择。屏幕外相邻单位仍沿用原有链式扩选。
- 建筑同类映射：遍历完整 `upgrade_to` Resource 引用链，为所有等级计算统一族根；按 ID 去重并限制上溯步数，避免循环引用造成无限遍历。升级形态仅加入选择映射，不加入直接建造目录。
- 此次修复复用项目投影函数、Godot Resource 引用和原生 Dictionary/Array；未引入依赖或新子系统，未新增测试脚本。

修复后检查（日志前缀 `.godot/bundle-c220110-fix-`）：导入及两个修改脚本的 `--check-only` 通过；既有回归 49 项、0 失败；普通/战役各 600 帧、既有压力入口 900 帧均通过，无脚本解析、编译或运行错误。另已启动原生图形窗口，渲染器与场景启动无脚本错误；原生操作工具返回 `Computer Use native pipe is unavailable`，无法继续鼠标双击及不同等级建筑的实际选择验收，已结束本轮启动的游戏进程。系统证书库和编辑器设置保存提示同下文，未计为项目脚本错误。

## 引入结果

- 文件：`billions-mech-0.5.89-dev-c220110.bundle`。
- `git bundle verify` 通过，依赖提交 `fe07dc4a6535cb6c433d6a098647abc408dbbb03` 与引入前的本地 HEAD 一致。
- `main` 已从 `fe07dc4` 快进至 `c2201109d90f87995e14209691df26ec845f01c2`，无合并冲突；原始 bundle 保留。
- 新增提交：`1fd5d46`（中文注释）、`d2654c9`（框选及双击选择）、`c220110`（游荡敌合并为建造者）。共影响 52 个文件。
- 注释提交的差异经排除整行及行尾注释核对，没有可执行逻辑变化。

## 原 bundle 发现的问题（均已修复）

### P1：双击选单位混用了逻辑格坐标和等距投影坐标

位置：`presentation/main.gd:735–741`。

`_camera.visible_world_rect()` 返回 Camera2D 使用的等距投影坐标矩形，而 `entity["position"]` 是模拟层逻辑格坐标。直接使用 `visible.has_point(entity["position"])` 无法判断单位是否位于屏幕内。

默认开局镜头在主脑附近，投影纵坐标约为 3000，而侦察机的逻辑纵坐标约为 68。因此屏幕内的侦察机会被排除，`units` 为空，后续链式扩选也不会执行，最终 `_selection.select(units)` 清空选择。

建议：先将单位位置经 `MechIsoGeometry.project()` 投影，再与该镜头矩形比较；或沿用 `_screen_position()`，在视口战场范围内判定。同时确保被双击的单位进入扩选起点。

### P2：建筑同类映射遗漏升级形态

位置：`sim/construction_system.gd:43–56`。

`_rebuild_family_roots()` 只遍历 `_definitions`；该表由 `settings.building_definitions` 装配，包含可配置的基础定义，升级形态主要通过 Resource 的 `upgrade_to` 引用加载。函数既没有完整遍历升级链，也没有为未注册的升级 ID 写入 `_family_roots`。

例如，`compute_node_ii` 和 `compute_node_iii` 未写入映射，`family_root()` 回退为它们自己的 ID；与基础 `compute_node` 的 family_id 不同。双击计算节点 I 无法选中计算节点 II/III，与操作说明中“升级前后视为同种”的承诺不符。当前配置有 21 个升级形态 ID 未进入映射。

建议：从每个基础定义完整遍历 `upgrade_to` 链，为沿途所有等级写入同一族根，并保留循环保护。

## 已执行的验证

| 检查 | 结果 |
| --- | --- |
| bundle 校验及基线祖先关系 | 通过 |
| Godot 4.7.2 headless 导入 | 未发现项目脚本解析或编译错误；有下述环境提示 |
| 46 个活动 GDScript 的逐文件 `--check-only` | 46/46 通过 |
| 既有 `validation/vision_checks.gd` | 49 项，0 失败 |
| 普通启动 | 600 帧通过，无脚本错误 |
| 战役启动 | 600 帧通过，无脚本错误 |
| 既有 `--stress --perf` 入口 | 900 帧通过，无脚本错误；并行检查结果不用于性能对比 |
| `git diff --check fe07dc4 c220110` | 通过 |

游荡形态标记已沿初始散布、边缘回填、创建、区域行军、索敌、脱战和胜利检查传递；感疫产物及波次生成默认仍为行军形态。运行代码未发现对已删除 `wanderer.tres` 的残留引用。既有回归已迁移到建造者定义，未新增测试脚本。

日志保存在 `.godot/bundle-c220110-{import,scripts,vision,normal,campaign,stress}.log`。环境提示为无法读取系统证书库，以及导入时不能向工作区之外的 Godot 安装目录保存编辑器设置；与项目脚本错误分开记录。

以上为原 bundle 的审查及检查记录；后续修复与复验见本文“修复结果”。本轮未完成原生鼠标交互验收、完整波次或战役通关验收。
