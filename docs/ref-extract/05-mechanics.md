# 05 - 机制提取（从代码逐条提取，带 来源文件:行号）

> 重要前提：本仓库**未实现任何玩法逻辑代码**（无战斗/商店/任务视图）。以下条目 = 数据模型字段、校验逻辑、后台配置与文案中**可确证的规则**；
> 标注「推断」的为设计意图而非已实现代码。

## 1. 地图系统

1. **地图 = excel 网格上传**：`Map.map_file` 为 FileField；`save()` 用 pandas 逐 sheet 读取，sheet 名 → `Map.name`（城市名），单元格内容 → `places` JSON（`map/models.py:18-30`）。多 sheet 会循环覆盖 name（bug，`map/models.py:22-26`），实际使用单 sheet。
2. **地点即格子名**：`places` JSON 键=列标签、值=「行标签→地点名」；空格子=null。玩家可达处 = 有名字的格子（db map id=5 实例）。
3. **城市是地图单位**：Monster.city/NPC.city 的 choices 动态取 `Map.objects.all()`（`monster/models.py:14-16`, `npc/models.py:8-10`）。
4. **落位校验**：怪物 `location`、NPC `default_place` 必须出现在该城市 places JSON 文本中（**字符串子串匹配**，非解析 JSON），否则拒绝保存（`monster/models.py:27-32`, `npc/models.py:22-29`）。
5. **NPC 游走预留**：NPC 有 `location`（当前）与 `default_place`（默认）双字段，location 为后台只读（`npc/admin.py`），推断由系统/事件驱动移动（`npc/models.py:5-12`）。

## 2. 玩家与属性

6. **初始属性（1 级）**：exp 0/100，hp 100/100，min_attack 1，max_attack 3，defense 1，agility 1，momentum 1，出生地 `['威尼斯','酒馆']`（`player/models.py:29-41` 字段默认值；DB 两测试玩家即此值）。
7. **位置存储格式**：`location = CharField`，内容为 Python list 的字符串形式 `"['威尼斯', '酒馆']"`（db player_playerstatus 实例），首页模板取 `[0]`城市 `[1]`地点（`templates/location.html:14`）。
8. **升级经验门槛**：初始 max_experience=100（`player/models.py:34`）；**成长曲线无任何代码**。后台将 `max_experience/max_attack/location` 设为只读（`player/admin.py PlayerStatusAdmin`），即升级由服务器逻辑控制（未实现）。
9. **注册即建状态**：admin 保存 User 时 `update_or_create` 一份 PlayerStatus（`player/admin.py:47-50, 79-82`）。
10. **属性七件套与怪物同构**：PlayerStatus 与 Monster 共有 max_health/min_attack/max_attack/defense/agility/momentum（`player/models.py:29-41` vs `monster/models.py:5-17`）→ 战斗为同套属性对抗。**momentum（士气）** 为本游戏特色属性，用途无代码（推断：先手/暴击/士气崩坏类 MUD 机制）。
11. **独立体力资源**：物品文案（体力宝/奶瓶/曲奇饼/火龙汤圆）表明存在与 HP 分离的「体力」值：恢复量 500/3000/8000/80000，**低于 50% 自动使用体力宝/奶瓶**，体力宝每人限持 2 个（`stuff_stuff.illustrate` id 7,8,11,12）。
12. **负重系统**：每件物品有 weight；乾坤袋 +50 负重可叠加（`stuff/models.py:35`, `stuff_stuff` id 10）。PlayerStuff.inventory 记录堆叠数量（`player/models.py:52-55`）。

## 3. 物品与装备

13. **五类型**：1武器 2护甲 3药品 4消耗品 5任务物品（`stuff/models.py:8-14`）。
14. **六品质**：普通/精良/稀有/完美/史诗/传奇（`stuff/models.py:15-22`）。
15. **武器词条**：min_attack 2 / max_attack 5 / agility 1 / slot 宝石插槽 / durability 350 / enhancement 基础强化等级 / quality（`stuff/models.py:46-54`）。样例：长剑 2-5、短锤 3-4。
16. **护甲词条**：defense 1 / agility 1 / lucky 幸运一击 / poison_resistance 毒抗 / slot / durability 350 / enhancement / quality（`stuff/models.py:65-74`）。
17. **交易绑定**：`is_tradable` 1/0；龙泉水强化后的装备「不可交易」（文案，id 17）→ 强化产生绑定装备；引路蜂默认不可交易。
18. **强化系统**：enhancement 字段 + 龙泉水文案（`stuff/models.py:49,68`）——强化改词条，强化后绑定（推断成功率/失败惩罚未实现）。
19. **宝石插槽**：slot 字段（`stuff/models.py:53,71`），粗制铜盔 slot=1。宝石类物品未录入。
20. **耐久**：默认 350（`stuff/models.py:54,73`），消耗/修理机制未实现。
21. **buff 卡片系统**：双倍经验卡（全经验来源 +100%，除副本，持续 1 小时，不可叠加）+ 还原卡（清除所有卡片效果）（id 9,15 文案）。
22. **经验渠道**：打坐（野球草人，10 级）、双倍经验卡除外「副本」——存在副本玩法概念（id 9,13 文案）。

## 4. 战斗（无代码，仅能确证的接口面）

23. 战斗输入 = 双方 {min/max_attack, defense, agility, momentum, max_health}（第 10 条同构性）；伤害公式、命中、先手判定**零实现**。复刻需自建；建议以 defense 减伤、agility 比先手、min-max 随机伤害为基线（原版 MUD 惯例，非本仓库证据）。

## 5. 经济/社会系统（无代码，物品/NPC/地点佐证的存在性）

24. 银行（地点）、赌场（地点+大世界图）、商店/市场/珠宝店/铁匠铺（地点）→ 规划了存取、赌博、买卖、修理打造，但**物品无价格字段、无货币字段**（PlayerStatus 无金钱属性——经济系统完全未建模）。
25. 钓鱼（小鱼活饵）、种田（牧草种子）、改名（改名卡 30 级）、副本、海皇宫殿潜水（NPC 西利亚 bio）→ 生活玩法清单。
26. 等级门槛实例：野球草人 10 级、改名卡 30 级、粗制铜盔 4 级（stuff_stuff.level）。

## 6. 前台/路由（可确证的全部玩家可见面）

27. 路由仅 4 条：`/admin/`、`/file/<media>`、`/static/<static>`、`/` 首页（`zhsh/urls.py:6-12`, `player/urls.py`）。
28. 首页 LocationView 为 DetailView(PlayerStatus.objects.first())，但 `templates = 'location.html'` 属性名写错（应为 `template_name`，`player/views.py:7-10`）→ 实际会渲染 `player/playerstatus_detail.html`（不存在）→ 首页当前是坏的，commit 信息「待完善首页」即此。
29. 前端为 Bootstrap 5 CDN + jQuery 3.6（`templates/base.html:11-13`）。

## 7. 对复刻最具决定性的事实

- **本仓库不是可玩的参照物，而是「数据字典 + 初始数据集」**。战斗/经济/任务公式必须另行设计或从他处考证。
- 属性模型、装备词条、物品清单、地图网格、出生设定可直接照搬（见 01/03/04/06 文档）。
- 「体力」「士气」「负重」「耐久」「插槽」「强化绑定」「buff 卡片」是原版机制存在性的硬证据，设计 Godot 版时应保留这些概念。
