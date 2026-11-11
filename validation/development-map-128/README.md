# 128×128开发地图检查

> 历史地图生成材料（0.5.25起）。JSON/导航/预览报告只证明各自记录版本，不是0.5.89重新生成的校验。当前地图/资源与运行规则见[地图专稿](../../docs/map-terrain.md)、[数值表](../../docs/values.md)，最近代码检查见[三维验证](../3d-interaction-performance.md)。`p1-bundle-validated.json`仍仅是P1阶段的校验快照；后续风口、水域和燃料已接入源/运行地图，不把旧截图、统计或哈希冒充当前。

当前开发图入口`content/development_128.tres`，使用正式`mainbrain.tres`（5×5）、600币/80金属矿和2侦察机。另有两张[新关卡](../tutorial-maps/README.md)，不属于本历史记录。下文的临时主脑、旧入口、旧钱包和旧训练场只作生成历史解释，不是可运行步骤。

2026-11-12已将当前源与原生地图改为等面积正方形展示边界，重新生成本目录`map-bundle.json`、`layout-report.json`：184×184包围网格、16042完整格、几何总面积保持原128×128＝16384平方格，1个可走连通区、34个锚点。其余旧bundle/nav/preview材料未重跑，仅对应旧布局，不能用于证明本次扩展后的路线。最新边界规则和验证见[地图规则](../../docs/map-terrain.md)、[新关卡与方形检查](../tutorial-maps/README.md)。

2026-11-08，0.5.25-dev。新默认地图为“四隘盆地”，复用现有Godot灰盒地形/实体渲染，`art_source=existing`，未生成或替换美术。数据由手工编排的多边形布局经Pillow栅格化，再适配现有`Rect2i`地图格式；连通分析复用SciPy和generate2dmap工具，未编写运行时随机地图生成或寻路算法。

## 入口与交付

- 默认启动：`content/development_128.tres`，由`presentation/main.gd`载入。
- 新地图：`content/maps/development_basin_128.tres`；布局源为同目录`.source.json`。
- 主脑：本场景使用`mainbrain_development.tres`，占地5×5，原有经济参数保留。旧`foundation.tres`、`first_outpost.tres`和训练场4×4主脑不改，供既有回归与训练使用。
- 原生总览：[development-map-128-overview.png](../../docs/screenshots/development-map-128-overview.png)。来自引擎电影模式导出；仅总览场景关闭迷雾显示，正常默认玩法仍有战争迷雾。
- 可行走的碰撞诊断：[preview.html](preview-final/preview.html)。这是俯视数据预览，不是替代原生等距美术。
- 再编译：在项目根目录执行`python tools/compile_development_map.py`；依赖现有Pillow、NumPy、SciPy。地图源、原生Resource与检查bundle同源，不能只改其中一个输出。

## 生成时布局与旧运行边界

| 项目 | 结果 |
|---|---|
| 逻辑/可玩区域 | 完整128×128，共16,384格，无旧四边形裁切 |
| 地形 | 开阔10,183格、崎岖1,561格、障碍4,640格 |
| 主脑与防线 | 主脑(61,61)、5×5；四方向主通路，外层/盆地/核心三层规划线 |
| 矿点 | 金属原料8处×720，当前映射旧`ore`；晶体5处×180，当前使用旧`rare`标记 |
| 燃料 | 6处×480仅在布局源中预留，不伪装成矿石，也未接入旧钱包 |
| 水域 | 3处规划水面当前为障碍占位，临水建筑与水面材质未实施 |
| 参考环境选址 | 开局风能评分30/参考15电；太阳能评分60/上限20电；扩张位分别24/12电、60/20电 |
| 启动布局 | 两处金属原料2×2采矿位置、参考风能/太阳能本体和中继位满足未来6格主脑覆盖；西侧燃料可由一段6格中继接入 |

上述环境评分是布局数据检查，当前尚无风能/太阳能运行系统；也没有提前切入600币、新节点容量或新冷却规则。旧经济继续运行：250币/50矿石、主脑电60/容量10/币2每分钟。保留基地28格禁刷区；完整地图按旧密度生成的游荡敌总量为94，旧图约32，不表示密度或移速提高。完整战斗节奏与大规模性能仍待实际试玩。

## 检查结果

| 检查 | 生成时结果 |
|---|---|
| 内容编译与SciPy连通 | 主脑占用后可行走地形仅1个连通分量；矿点与建设位均有合法地形 |
| [bundle校验](bundle-validated.json) | pass，0 errors、0 warnings |
| [导航检查](nav-final/nav-report.json) | pass，34目标可达、0不可达、0薄缝；已查看[诊断图](nav-final/nav-debug.png) |
| [预览运行时路线](preview-final/runtime-route-report.json) | `ok=true`，34/34；直接执行预览HTML内同版map-runtime和规范化数据，保存[scene-snapshot.json](preview-final/scene-snapshot.json) |
| Godot原生导入/脚本 | 项目脚本语法检查，无SCRIPT/Parse/Compile错误；系统环境错误另列于下 |
| 标准新图/原训练场 | 各600帧无脚本运行错误 |
| 既有视野回归 | 49 checks，0 failures；仍使用原版fixture，不新增测试脚本 |
| 原生渲染 | 1920×1080导出并查看4帧总览，主脑详情显示5×5；普通场景迷雾保持启用 |
| 人工玩法 | 鼠标建拆、四波实战、三幕经济尚未完成，不能以静态连通与启动替代 |

浏览器验证限制：工具自带Playwright核验因本机未安装该包而SKIPPED。尝试Edge调试连接未完成自动化，因此只报告Node直接运行同版预览路线检查，不声称浏览器键盘/Y-sort验收通过。原生游戏另行完成导入、启动和画面导出。

Godot日志位于忽略目录`.godot/development-map-*`。环境提示为`Failed to read the root certificate store.`及Steam编辑器全局`editor_settings-4.7.tres`保存失败；不是地图脚本错误。

## 能力检查提示原文

来自[doctor.json](doctor.json)的四项WARN原样保留。它们不是本次bundle/nav QA的WARN；本次不使用视频、SVG代码美术或缺失的角色技能。

| id | value/detail（原文） | threshold | files |
|---|---|---|---|
| python.path | `other python.exe on PATH: ~/AppData/Local/Microsoft/WindowsApps/python.exe` | 未提供 | `doctor.json` |
| paths.cwd | `the working folder has spaces or non-ASCII characters` | 未提供 | `doctor.json` |
| skills.present | `~/.codex/skills: missing generate2dsprite, video2dsprite, codeart2d` | 未提供 | `doctor.json` |
| ffmpeg | `C:/ffmpeg/bin/ffmpeg.EXE: development build 2024-07-10-git-1a86a7a48d-full_build-www.gyan.dev; 5.1+ cannot be confirmed` | 未提供 | `doctor.json` |

初次bundle缺失provenance字段、初次未挂载anchor approach导致未覆盖路线的问题已修正，并重新生成当前报告；初次报告已移入`.godot`，不作为当前验收结果。
