# RTS Advanced Lite — 编队数学模块

来源：[openclawaimac/godot-rts-advanced-lite](https://github.com/openclawaimac/godot-rts-advanced-lite)，锁定提交 `81e757ba2f144c10c18bc21daa06a6b0593661d3`（2026-10-17 UTC），MIT © 2026 Huginhelm，许可全文见 `LICENSE`。

`rts_formation.gd` 为上游原文件，逐字保留。直接使用 `RTSFormation.box` 和 `RTSFormation.assign`；未引入框架的 Node3D 单位、寻路、避让或选择模块。

本模块虽然使用 Vector3，但纯数学位于 XZ 平面，不依赖场景。`sim/formation_planner.gd` 负责二维坐标转换、命令方向、旧偏移复用、成员排序与地形/可达性校验；`sim/entity_state.gd` 与表现层负责朝向。`assign` 为贪心匹配，不承诺全局最优或绝对不交叉。

源码 SHA256：`0AABB82B181821386AE4F9BAE3121A23D99D6522D8E6CC99D6D6831355C27327`。核查与选型见 [复用调研 §17](../../docs/reuse-research.md)。
