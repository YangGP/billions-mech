# 重启记录：M0 / M1

日期：2026-11-04。基线：在原仓库根目录重新开发，无独立子工程。

> 本页为重启当时的实施记录，“当前状态与下一步”不表示最新进度。当前状态见根目录 [README](../README.md) 和 [开发计划](../docs/development-plan.md)。

## 已实施

- 删除 `scripts/` 中全部 28 个旧 `.gd` 及其 28 个 UID；旧游戏逻辑不再加载。
- 旧场景、数据、图像、字体和导入缓存移到 `archive/legacy-prototype/`。自动审批曾拒绝同时递归删除这些非代码目录，故采用不丢失内容的本地归档方案；归档有 `.gdignore`，不参与新工程导入。
- 全新根项目配置与主场景；新代码位于 `sim/`、`commands/`、`presentation/`、`content/`。
- 纯数据时钟/实体/注册表/模拟核心，串行命令入口，只读快照视图；接入设置目标、暂停/继续和重开命令。
- 新视图为程序绘制的灰盒平台、主脑与验证实体，没有复用旧贴图或旧运行代码。

## 模块选择与依据

| 模块 | 本轮选择 | 依据与当前验证范围 |
|---|---|---|
| 固定步长驱动 | Godot 4.7.2 内置 `_physics_process`，30 Hz | [官方固定频率处理说明](https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html)；已接入新工程并完成语法与启动检查 |
| 纯数据状态 | Godot 内置 RefCounted、Dictionary、Vector2 | 无第三方依赖；本项目代码只装配实体生命周期、状态快照与移动验证 |
| 命令入口 | RefCounted + Callable + 短生命周期串行队列 | 本项目需要暂停中即时提交与拒绝反馈；没有引入录制或网络生命周期 |
| 玩家 A* | 优先采用内置 AStarGrid2D，待 M2/M4 接入 | [官方 API](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html) 已核对；当前尚未编写寻路适配，不声称场景验证通过 |
| 选择/编队/生产/战斗 | RTS Advanced Lite 等已有方案待按模块验证 | 已核对 [上游 README](https://github.com/openclawaimac/godot-rts-advanced-lite#readme) 的 3D/Lite 边界；未导入 vendor，也未验证源码耦合度 |
| 2D 相机/流场 | Crusade 等候选待验证 | [上游 README](https://github.com/saman-mb/crusade-rts#readme) 要求 4.4.1；不能当作已适配 4.7 的成品 |

外部模块详见 [复用调研](../docs/reuse-research.md)。本环境没有 Agent-Reach；shell 外网访问失败，网页检索可读 README 与官方文档，但部分上游源码 URL 获取失败。没有据此宣称依赖已经锁定或完成接入。

## 已执行校验

- Godot 4.7.2：`--headless --editor --import --quit`，全新全局类缓存只注册新项目类。
- 对 9 个新 `.gd` 逐一运行 Godot `--check-only --script`，均退出 0，无 GDScript 解析/编译错误。
- 新主场景无头启动至 `--quit-after 30`，输出 M1 ready，未出现脚本加载/运行错误。
- 未新增测试脚本。交互正确性和视觉布局尚待人工运行确认，不把无头启动等同于全部验收完成。

环境诊断：受限环境读取 Windows 根证书库失败；Steam 自包含编辑器退出时不能写入引擎安装目录的 editor settings。相对日志路径会落到 user://，后续检查与 run.bat 使用项目内绝对日志路径。这些诊断不等同于脚本错误；未修改引擎安装目录或系统权限。

## 当前状态与下一步

- M0：初始规格和核心模块选择已记录，完整外部模块适配/规模预算未完成。
- M1：基础代码与运行入口已实现，语法/启动检查通过，交互验收待人工确认。
- M2–M10：未开始。下一步建立真实地图、三类地形、占用、相机和空间校验；当前移动验证不承担正式寻路和碰撞规则。
