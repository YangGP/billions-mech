# 当前数值（0.5.89-dev）

2026-11-09 按 `content/` 的实际 Resource、默认字段及模拟常量核对；不是正式平衡结论。旧四项钱包、250币开局、冷却未来稿及逐批追加的历史数值已移除，原始设计推导保留于[资源V1](resource-building-proposal-v1.md)和[建筑V2](building-roster-v2.md)。

## 1. 经济标尺

库存ID固定 `coins/metal_ore/fuel/alloy/crystals`。下表费用缩写按**币/金属矿/合金/晶体**排列，0不可省略；燃料仅在运营配方中另列。材料是整数、产率为每分钟、时间为秒、距离为逻辑格、冷却内部为十分之一点整数。

图纸给额定能力，实例决定运行产量：环境电源按地格、冶炼按燃烧周期、光环按实际范围/连通。下表不能替代位置、科技、历史产出、供给及会话状态校验。

## 2. 全局时间与开局

| 项 | 当前配置 |
| --- | --- |
| 唯一玩法配置 | `content/development_128.tres` |
| 地图/主脑 | 128×128“四隘盆地” / 各级5×5 |
| 模拟频率 | 30 Hz |
| 启动库存 | 600币、80金属矿，其余0 |
| 启动单位 | 2侦察机，无免费诊断实体 |
| 首波 | TIME_ONLY；570s静默、30s预告，9:30预告/10:00出兵 |
| 后续出兵间隔/流式窗口 | 600s / 300s |
| 默认模式 | 4波，全部出完并清除行军/交战敌后判胜 |
| 战役候选 | `--campaign`；持续波次直到满足前置请求终波 |
| 会话种子 | 1，当前用于合同随机序列，非全模拟存档/回放保证 |

## 3. 主脑与节点

| 形态 | 占地 | HP | 总/系统/净调度 | 电供给/需求 | 冷供给/需求 | 币/min | 覆盖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [主脑 I](../content/buildings/mainbrain.tres) | 5×5 | 4000 | 8/2/6 | 10/0 | 4/0 | 4 | 6 |
| [主脑 II](../content/buildings/mainbrain_ii.tres) | 5×5 | 5000 | 12/3/9 | 10/0 | 4/0 | 6 | 6 |
| [主脑 III](../content/buildings/mainbrain_iii.tres) | 5×5 | 6000 | 16/4/12 | 10/0 | 4/0 | 8 | 6 |
| [算力节点](../content/buildings/compute_node.tres) | 2×2 | 250 | 4/1/3 | 0/2 | 0/2 | 6 | 0 |
| [算力节点 II](../content/buildings/compute_node_ii.tres) | 2×2 | 500 | 8/2/6 | 0/4 | 0/4 | 14 | 0 |
| [算力节点 III](../content/buildings/compute_node_iii.tres) | 2×2 | 800 | 12/3/9 | 0/7 | 0/6 | 24 | 0 |

主脑不可另建；节点系统自用已从总算力中扣除，不再重复占净调度。运营服务只由完工且连通的建筑提供。

## 4. 基础建筑目录

31类按菜单顺序列出；主脑也计1类。前置列为图纸要求的科技/主脑最低级别，额外历史产出门槛见下文。

| 建筑 | 占地 | 新建费（币/矿/合/晶） | 工期 | HP | 调度/电/冷需求 | 科技/主脑 |
| --- | --- | --- | --- | --- | --- | --- |
| [算力节点](../content/buildings/compute_node.tres) | 2×2 | 30/4/0/0 | 40 | 250 | 0/2/2 | 0/0 |
| [资源调配站](../content/buildings/resource_depot.tres) | 3×3 | 180/16/8/0 | 50 | 500 | 2/3/0 | 2/2 |
| [负载均衡站](../content/buildings/load_balancer.tres) | 3×3 | 200/16/10/0 | 50 | 500 | 2/4/0 | 2/2 |
| [结算中心](../content/buildings/settlement_center.tres) | 3×3 | 260/16/16/0 | 60 | 600 | 2/4/0 | 2/2 |
| [远征接驳站](../content/buildings/expedition_dock.tres) | 3×3 | 300/20/12/0 | 60 | 600 | 2/4/0 | 2/2 |
| [金属采矿站](../content/buildings/mining_station.tres) | 2×2 | 40/0/0/0 | 30 | 250 | 1/2/0 | 0/0 |
| [燃料采集站](../content/buildings/fuel_extractor.tres) | 2×2 | 50/8/0/0 | 35 | 250 | 1/2/0 | 0/0 |
| [晶体采掘站](../content/buildings/crystal_extractor.tres) | 2×2 | 120/10/8/0 | 45 | 350 | 2/4/0 | 0/3 |
| [风能站](../content/buildings/wind_station.tres) | 1×1 | 60/8/0/0 | 30 | 250 | 0/0/0 | 0/0 |
| [太阳能站](../content/buildings/solar_station.tres) | 2×2 | 50/6/0/0 | 30 | 250 | 0/0/0 | 0/0 |
| [热能冶炼站](../content/buildings/thermal_smelter.tres) | 3×3 | 120/18/0/0 | 45 | 500 | 0/0/0 | 0/0 |
| [中继节点](../content/buildings/relay_node.tres) | 1×1 | 15/2/0/0 | 10 | 150 | 0/1/0 | 0/0 |
| [冷却塔](../content/buildings/cooling_tower.tres) | 2×2 | 50/6/0/0 | 25 | 250 | 0/1/0 | 0/0 |
| [水冷站](../content/buildings/water_cooler.tres) | 2×2 | 60/6/0/0 | 25 | 250 | 0/1/0 | 0/0 |
| [装甲墙](../content/buildings/armored_wall.tres) | 1×1 | 2/1/0/0 | 8 | 400 | 0/0/0 | 0/0 |
| [闸门](../content/buildings/gate.tres) | 1×2 | 8/4/0/0 | 12 | 800 | 0/0/0 | 0/0 |
| [驻防碉堡](../content/buildings/garrison_bunker.tres) | 2×2 | 60/10/0/0 | 35 | 600 | 0/0/0 | 0/0 |
| [哨戒炮塔](../content/buildings/sentry_tower.tres) | 2×2 | 80/8/0/0 | 40 | 600 | 2/3/0 | 0/0 |
| [速射机炮](../content/buildings/rapid_cannon.tres) | 1×1 | 90/6/4/0 | 30 | 250 | 1/2/0 | 2/2 |
| [电弧塔](../content/buildings/arc_tower.tres) | 2×2 | 220/10/18/0 | 65 | 750 | 3/7/0 | 2/2 |
| [减速栅](../content/buildings/slow_fence.tres) | 1×1 | 6/2/0/0 | 6 | 100 | 0/0/0 | 0/0 |
| [电磁陷阱](../content/buildings/emp_trap.tres) | 1×1 | 12/2/2/0 | 10 | 100 | 0/0/0 | 2/2 |
| [爆破地雷](../content/buildings/blast_mine.tres) | 1×1 | 18/2/3/0 | 8 | 80 | 0/0/0 | 2/2 |
| [组装厂](../content/buildings/assembly_plant.tres) | 3×3 | 100/10/0/0 | 60 | 800 | 2/4/0 | 0/0 |
| [重装工厂](../content/buildings/heavy_factory.tres) | 3×3 | 400/20/24/0 | 90 | 1000 | 4/8/0 | 2/2 |
| [主脑 I](../content/buildings/mainbrain.tres) | 5×5 | 0/0/0/0 | 1 | 4000 | 0/0/0 | 0/0 |
| [科技中心 I](../content/buildings/tech_center.tres) | 2×2 | 120/10/6/0 | 60 | 400 | 2/4/0 | 0/0 |
| [瞭望哨](../content/buildings/lookout_post.tres) | 1×1 | 25/4/0/0 | 15 | 200 | 0/1/0 | 0/0 |
| [雷达站](../content/buildings/radar_station.tres) | 2×2 | 120/8/4/0 | 45 | 300 | 1/4/0 | 2/2 |
| [维修站](../content/buildings/repair_station.tres) | 2×2 | 120/8/8/0 | 50 | 400 | 1/4/0 | 2/2 |
| [调度中心](../content/buildings/dispatch_center.tres) | 3×3 | 600/20/30/16 | 120 | 1200 | 4/6/0 | 3/3 |

科技 I 需首次真实合金产出；科技 III 还需历史晶体产出。首晶体站需主脑 III，主脑升 III 和首站本身不耗晶体。直接建造/升级/合同/生产仍走模拟层前置，不能单看此列判断全部可用性。

## 5. 升级差价与时间

当前共22个升级目标，每级独立不可变定义。下列为**本次差价**，不是新建总价；主脑升级不可取消，其他升级取消退本次未完成差价。升级后完整能力以链接的目标 Resource 为准。

| 当前→目标 | 差价（币/矿/合/晶） | 用时 | 目标HP | 目标调度/电/冷需求 |
| --- | --- | --- | --- | --- |
| [电弧塔](../content/buildings/arc_tower.tres)→[电磁塔](../content/buildings/emp_tower.tres) | 130/2/2/8 | 60 | 900 | 3/8/0 |
| [装甲墙](../content/buildings/armored_wall.tres)→[合金墙](../content/buildings/alloy_wall.tres) | 4/0/2/0 | 6 | 900 | 0/0/0 |
| [算力节点](../content/buildings/compute_node.tres)→[算力节点 II](../content/buildings/compute_node_ii.tres) | 60/4/6/0 | 40 | 500 | 0/4/4 |
| [算力节点 II](../content/buildings/compute_node_ii.tres)→[算力节点 III](../content/buildings/compute_node_iii.tres) | 120/4/6/4 | 60 | 800 | 0/7/6 |
| [冷却塔](../content/buildings/cooling_tower.tres)→[强化冷却塔](../content/buildings/cooling_tower_ii.tres) | 100/4/8/0 | 50 | 500 | 0/3/0 |
| [晶体采掘站](../content/buildings/crystal_extractor.tres)→[深层晶体采掘站](../content/buildings/crystal_extractor_deep.tres) | 180/6/12/8 | 60 | 600 | 3/7/0 |
| [燃料采集站](../content/buildings/fuel_extractor.tres)→[深层燃料采集站](../content/buildings/fuel_extractor_deep.tres) | 100/4/8/0 | 45 | 500 | 2/4/0 |
| [驻防碉堡](../content/buildings/garrison_bunker.tres)→[合金碉堡](../content/buildings/alloy_bunker.tres) | 80/4/10/0 | 45 | 1400 | 0/0/0 |
| [闸门](../content/buildings/gate.tres)→[合金闸门](../content/buildings/alloy_gate.tres) | 12/0/4/0 | 10 | 1600 | 0/0/0 |
| [重装工厂](../content/buildings/heavy_factory.tres)→[高级重装工厂](../content/buildings/advanced_heavy_factory.tres) | 400/10/16/20 | 90 | 1500 | 6/12/0 |
| [重型炮塔](../content/buildings/heavy_tower.tres)→[歼灭炮塔](../content/buildings/annihilator_tower.tres) | 200/6/14/12 | 75 | 1400 | 4/10/0 |
| [主脑 I](../content/buildings/mainbrain.tres)→[主脑 II](../content/buildings/mainbrain_ii.tres) | 800/40/30/0 | 180 | 5000 | 0/0/0 |
| [主脑 II](../content/buildings/mainbrain_ii.tres)→[主脑 III](../content/buildings/mainbrain_iii.tres) | 1600/80/60/0 | 240 | 6000 | 0/0/0 |
| [金属采矿站](../content/buildings/mining_station.tres)→[深层金属采矿站](../content/buildings/mining_station_deep.tres) | 100/4/8/0 | 45 | 500 | 2/4/0 |
| [哨戒炮塔](../content/buildings/sentry_tower.tres)→[重型炮塔](../content/buildings/heavy_tower.tres) | 120/2/16/0 | 60 | 1000 | 3/6/0 |
| [减速栅](../content/buildings/slow_fence.tres)→[合金减速栅](../content/buildings/alloy_slow_fence.tres) | 6/0/2/0 | 6 | 200 | 0/0/0 |
| [太阳能站](../content/buildings/solar_station.tres)→[强化太阳能站](../content/buildings/solar_station_ii.tres) | 90/4/8/0 | 45 | 500 | 0/0/0 |
| [科技中心 I](../content/buildings/tech_center.tres)→[科技中心 II](../content/buildings/tech_center_ii.tres) | 200/10/16/0 | 90 | 600 | 3/6/0 |
| [科技中心 II](../content/buildings/tech_center_ii.tres)→[科技中心 III](../content/buildings/tech_center_iii.tres) | 400/16/24/12 | 120 | 900 | 4/10/0 |
| [热能冶炼站](../content/buildings/thermal_smelter.tres)→[强化热能冶炼站](../content/buildings/thermal_smelter_ii.tres) | 120/4/10/0 | 60 | 800 | 0/0/0 |
| [水冷站](../content/buildings/water_cooler.tres)→[强化水冷站](../content/buildings/water_cooler_ii.tres) | 100/4/8/0 | 50 | 500 | 0/3/0 |
| [风能站](../content/buildings/wind_station.tres)→[强化风能站](../content/buildings/wind_station_ii.tres) | 100/4/8/0 | 45 | 500 | 0/0/0 |

## 6. 供给、采集和功能参数

| 功能 | 参数 |
| --- | --- |
| 中继 | 覆盖半径6，耗电1，1×1，只扩范围不发电 |
| 冷却塔 I/II | 供冷12/32，耗电1/3 |
| 水冷 I/II | 供冷20/40，耗电1/3，2×2，须正交邻水 |
| 风能 I/II | 1×1本体、7×7采集区，`min(18, floor(score/4))`；强化×2封顶36 |
| 太阳能 I/II | 2×2本体、8×8采集区，`min(20, floor(score/2))`；强化×2封顶40 |
| 热能冶炼 I | 每15s扣2燃料，可选1金属→1合金，燃烧供30电 |
| 热能冶炼 II | 每15s扣4燃料，可选2金属→2合金，燃烧供80电 |
| 金属/深层金属 | 12/24每分钟，8矿点×720初始储量 |
| 燃料/深层燃料 | 8/16每分钟，6矿点×480初始储量 |
| 晶体/深层晶体 | 3/6每分钟，5矿点×180初始储量 |
| 资源调配站 | 半径8，金属/燃料采集+15%，不加晶体 |
| 负载均衡站 | 半径8，节点冷却需求−20% |
| 结算中心 | 半径8，节点产币+20% |
| 驻防/合金碉堡 | 4名卫兵，射程+2/+3；不接侦察/重装 |
| 接驳合同 | 180s一份，60s交付，币150%/其余材料正常，容量接单预留 |
| 维修站 | 半径5，一次1目标，8HP/s，按实际HP付料 |
| 减速栅/合金栅 | 格上速度75%/65%，每次进入扣10耐久，HP100/200 |
| 电磁陷阱 | 半径2，速度40%，3s，一次性 |
| 爆破地雷 | 半径2，伤害120，一次性 |
| 瞭望哨/雷达 | 视野12/20；雷达提前20s，取运行雷达最大提前量 |

光环来源和目标必须连通，目标适用状态按各规则；同类取最强。环境电源排除本体/障碍/未知格，同类采集区排他；不按天气或昼夜变化。合金周期升级等旧周期结算后切换。

### 武器参数

| 建筑 | 伤害/间隔 | 射程 | 溅射半径 | 速度倍率/控制秒 |
| --- | --- | --- | --- | --- |
| [歼灭炮塔](../content/buildings/annihilator_tower.tres) | 40/0.75 | 9 | 1.5 | 1/0 |
| [电弧塔](../content/buildings/arc_tower.tres) | 30/3 | 5 | 3 | 1/0 |
| [电磁塔](../content/buildings/emp_tower.tres) | 40/3 | 6 | 3 | 0.7/3 |
| [重型炮塔](../content/buildings/heavy_tower.tres) | 72/3 | 9 | 0 | 1/0 |
| [速射机炮](../content/buildings/rapid_cannon.tres) | 7/0.5 | 6 | 0 | 1/0 |
| [哨戒炮塔](../content/buildings/sentry_tower.tres) | 30/2.5 | 8 | 0 | 1/0 |

控制取当前有效最强倍率，不叠乘；不同倍率独立到期，弱长控制不延长强短控制。射程、实时可见与地形 LOS 同时参与命中判定。

## 7. 维修与退款

手动维修4HP/s，当前有效新建配方25%为整条HP的满修标尺；逐资源整数余数累计，付款后回血。交战半径6，每0.5s检查脱战；施工/拆除/基座不能维修。维修站8HP/s沿用付料及交战规则。

取消施工/未交付生产/合同全退实付；拆除退累计实付50%向下取整，主动拆完退未结周期投入和未交付订单；敌毁不退款。重建按已完成等级新建价50%重新付费并申请额度。区域预算仅记录真实消费/退款责任，不是第二个钱包。

## 8. 开局账面核对

主脑净调度6，2侦察机合计占2，余4；电10、冷却4。基础节点每座需电2/冷2并增加净调度3、收入6/min。此处只解释开局账目，**不证明十分钟发展路线、首波或完整经济已平衡**；原V1路线是历史设计样本。

## 9. 待校准

正式首波发展度公式/阈值、工业和升级窗口、四波强度、三阶段独立构成、终波与退守、自动化策略，以及规模性能均须常速验收。当前既有检查通过不作为平衡结论。

## 10. 单位

| 单位 | 配方（币/矿/合/晶） | 工期 | 调度 | HP | 伤害/间隔 | 射程/索敌 | 移速 | 视野 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [侦察机](../content/units/scout.tres) | 20/2/0/0 | 12 | 1 | 60 | 6/1 | 4/6 | 3 | 9 |
| [卫兵](../content/units/sentinel.tres) | 20/2/0/0 | 20 | 2 | 100 | 10/0.8 | 4/6 | 2.5 | 7 |
| [重装机甲](../content/units/heavy_mech.tres) | 160/6/10/0 | 60 | 4 | 700 | 45/1.5 | 5/7 | 1.8 | 7 |
| [磁轨机甲](../content/units/rail_mech.tres) | 320/8/18/12 | 90 | 6 | 600 | 180/3 | 9/11 | 1.8 | 9 |

侦察机目前是地面单位。组装厂队列5、重装/高级重装厂队列3；下单预留调度，出厂不再次占用。

## 11. 敌种

| 敌种 | HP | 单位/建筑伤害 | 间隔 | 速度 | 视野 | 威胁单价 |
| --- | --- | --- | --- | --- | --- | --- |
| [建造者](../content/enemies/builder.tres) | 30 | 6/6 | 1 | 1.5 | 6 | 1 |
| [游荡敌](../content/enemies/wanderer.tres) | 15 | 3/3 | 1 | 0.35 | 5 | 0.5 |
| [回收者](../content/enemies/recycler.tres) | 400 | 25/25 | 2 | 1 | 6 | 5 |
| [原型机](../content/enemies/prototype.tres) | 900 | 10/40 | 1 | 0.8 | 9 | 40 |

原型机庇护半径6，覆盖自身和附近敌军，伤害乘0.5，同类庇护不叠加，源死亡即失效；只穿墙家族，不穿门、其他建筑或岩体。具体路径/锁定规则见敌种专稿。

## 12. 波次预算曲线

基础预算 `25 × 1.6^(波序−1)`；战役按主脑阶段乘1/1.5/2.2。第3波起放入一台原型机；第2波起或战役阶段II起，余预算25%用于回收者，其余用建造者填充。侧翼频率4；这仍是简化构成，未提供完整分阶段独立池。

终波预算2000，主脑III＋科技III可请求，下一波从全线边界流式出生。公开状态为 requested→releasing→clearing→complete，失败为failed；最后一波已排队不等于清场完成。重开恢复配置波数及阶段。

发展度模式仍有旧8节点和候选DEVELOPMENT_SCORE阈值24，但正常开发配置为TIME_ONLY。候选评分、正式采用与平衡结论分开，不能从存在字段推断已被验收。

## 13. 半径族

| 事件/来源 | 半径或提前量 |
| --- | --- |
| 战斗/施工/运转/移动噪声 | 24/12/6/8 |
| 原型机庇护 | 6 |
| 建筑交战维修暂停 | 6 |
| 经济光环 | 8 |
| 中继覆盖 | 6 |
| 雷达额外预告 | 20s，取最大运行源 |

## 14. 感染

建筑按显式 `infectable` 判定，不能按是否占调度推断。资源价值权重为币1、金属2、燃料2、合金3、晶体10，换算除数20；单位按自身定义价值处理。主脑走失败路径，墙/门/陷阱等豁免依定义。敌毁与主动取消/拆除严格区分。

## 15. 游荡敌参数

主脑占地安全半径28，开局散布和边缘回填共用。游荡敌基础速度0.35格/s，未交战倍率0.5，开阔地游荡/闻声为0.175格/s，追击0.35格/s；无噪声每8s有50%概率在2格内挪动。崎岖地还受移动权重影响。

开局94只为当前开发图启动记录，不是所有图固定数量。历史调速及性能测量见[专题](../validation/performance-wanderers.md)，不宣称精确复刻参考游戏速度。

## 16. 数据源与维护

- `content/development_128.tres` 覆盖启动值，不能把 `foundation_settings.gd` 的兼容默认250币当作正常开局。
- 建筑、单位、敌种、配方分别以对应 Resource 为依据；实例供电/光环/余数由模拟结算。
- 新参数改动须同步本表和对应规则，旧测量只保留在明确版本的验证记录，不再逐批向本表追加另一套“当前值”。
- 本次仅静态核对配置与文档，没有执行新玩法验收，也没有改变任何数值或代码。
