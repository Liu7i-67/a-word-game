# 扩展契约定书 · 城外野外 + 药品 + 铁匠 + 威尼斯地宫

> 本文件是本轮扩展的唯一契约。两个实施方按此分工，**不得越界改文件**：
> - **代理 A（内容数据）**：只改 `data/*.json`
> - **代理 B（机制实现）**：只改 `scripts/**`
> id、字段名、公式以下表为准，双方不得自行改名。

## 0. 现状速览

- 事件分发：`scripts/game/event_router.gd`（`handle(event)`，事件格式 `cmd:arg:arg2`）
- 页面：`scripts/game/pages.gd`（BBCode 构建器）；物品分类页已有 `items:equip|gem|drug|other`
- 玩家状态：`scripts/autoload/player_state.gd`（class_name PlayerCore，校验集中于此）
- 战斗：`scripts/game/combat_engine.gd`（一回合=玩家先手+怪还手；胜利发经验/铜贝/掉落）
- 数值公式：`scripts/game/rules.gd`（只写公式，数值在 `data/config.json`）
- 现有物品 type：`equip`（atk/durability/req_level/weight/stack=1）、`goods`（buy_price/sell_price/tiers/weight/stack）
- 市场 `_sell` 的卖出价 = `Rules.sell_price(buy_price)` = buy_price×50%，卖货页显示用 `sell_price` 字段

## 1. 场景表（代理 A 写入 data/scenes.json）

每个新场景：`on_map: false`（城内地图不含城外）、描述 1-2 句地中海风格中文、出口与接入它的城门**双向**互连。同时把下表「接入点」对应场景里的 `locked` 出口改为 `{"dir": 原方向, "to": 新场景id}`（删除 name/locked 字段）。实验室同时接入教堂东出口和占星屋南出口。

| 场景 id | 名称 | 接入点（改哪个 locked exit） | 城外回程出口 |
|---|---|---|---|
| nungcoeng1 | 威尼斯农场1 | 农场 nungcoeng 的东出口 | 北→nungcoeng |
| coujin | 威尼斯草原 | 南城门 naamsingmun 的西出口 | 东→naamsingmun |
| moucoeng | 威尼斯牧场 | 南城门 naamsingmun 的南出口 | 北→naamsingmun |
| haitan | 威尼斯海滩 | 东城门 dungsingmun 的东出口 | 西→dungsingmun |
| tsienhoi | 威尼斯浅海 | 东城门 dungsingmun 的南出口 | 北→dungsingmun |
| ngoanzo | 威尼斯暗礁 | 东城门 dungsingmun 的北出口 | 南→dungsingmun |
| kuaangsan | 威尼斯矿山 | 北城门 baksingmun 的北出口 | 南→baksingmun |
| zamlam | 威尼斯森林 | 西城门 saisingmun 的北出口 | 南→saisingmun |
| mezai | 威尼斯湿地 | 西城门 saisingmun 的西出口 | 东→saisingmun |
| hongjoe | 威尼斯荒野 | 西城门 saisingmun 的南出口 | 北→saisingmun |
| soenmon | 威尼斯实验室 | 教堂 gaautong 的东出口 + 占星屋 zimsinguk 的南出口 | 西→gaautong 北→zimsinguk（两条） |
| gucyunlei | 威尼斯古村落 | 住宅区 zyuzaakkeoi 的东出口 | 西→zyuzaakkeoi |
| zozik | 威尼斯沼泽 | 住宅区 zyuzaakkeoi 的南出口 | 北→zyuzaakkeoi |
| hauwaan | 威尼斯后山 | 住宅区 zyuzaakkeoi 的北出口 | 南→zyuzaakkeoi |
| digung | 威尼斯地宫 | **特殊**：不接出口；探险官进入（代理 B 实现）。场景 npcs 必须含 `{"id":"keeper","name":"秘密看守","kind":"dungeon_keeper"}`；exits 为空数组；desc 写地宫氛围 | — |

## 2. 怪物表（代理 A 写入 data/monsters.json）

字段同现有 bingji：`name/level/hp/atk[min,max]/def/exp[min,max]/copper[min,max]/drop_rate/drop_item/instances`。instances 一律 5。

**数值公式**（按 level=L 计算，四舍五入）：
- `hp = round(40 * L^1.2)`
- `atk = [3+2L, 8+3L]`
- `def = round(5 + 1.5L)`
- `exp = [round(0.8L)+1, 4L+5]`
- `copper = [5L, 15L+10]`

| 怪物 id | 名称 | L | 场景 | 材料掉落（drop_item / drop_rate） |
|---|---|---|---|---|
| feng_e | 疯鹅 | 2 | nungcoeng1 | emao / 50 |
| ye_lang | 野狼 | 3 | coujin | langpi / 50 |
| sha_dao | 沙盗 | 4 | haitan | shajinshi / 50 |
| gong_niu | 公牛 | 5 | moucoeng | niupi / 45 |
| hai_yao | 海妖触手 | 6 | tsienhoi | haizao / 50 |
| du_she | 毒蛇 | 6 | zamlam | duyan / 50 |
| kuang_dao | 矿盗 | 7 | kuaangsan | tiekuangshi / 55 |
| hei_xiong | 黑熊 | 8 | zamlam | xiongdan / 40 |
| shi_mo | 石魔 | 9 | kuaangsan | xuantie / 50 |
| jiao_shi_xie | 礁石蟹 | 9 | ngoanzo | zhenzhu / 25 |
| ju_e | 巨鳄 | 10 | mezai | eyupi / 45 |
| liu_lang_jian_ke | 流浪剑客 | 11 | hongjoe | canjian / 50 |
| jue_mu_ren | 掘墓人 | 12 | gucyunlei | muzhuan / 50 |
| lian_jin_shi_bai_ti | 炼金失败体 | 13 | soenmon | lianjinzha / 50 |
| zhao_ze_xing_shi | 沼泽行尸 | 14 | zozik | shidunang / 45 |
| shan_zei_tou_mu | 山贼头目 | 16 | hauwaan | shanzei_lingpai / 30 |
| qiang_jie_zhe | 抢劫者 | 8 | digung（任务怪） | 无掉落（drop_rate=0, drop_item=""） |

已有限定：武器掉落见 §3（不是 drop_item 字段——武器只通过打造和固定两把掉落获得，怪物的 drop_item 只放材料）。

## 3. 物品表（代理 A 写入 data/items.json 的 items 下）

### 3.1 材料（type=goods，weight=0，stack=999，tiers=[]，只卖不买：`buy_price = 2×sell_price`、`sell_price` 如下）

| id | 名称 | sell_price | id | 名称 | sell_price |
|---|---|---|---|---|---|
| emao | 鹅毛 | 6 | duyan | 毒牙 | 26 |
| langpi | 狼皮 | 10 | xiongdan | 熊胆 | 30 |
| haizao | 海藻 | 8 | eyupi | 鳄鱼皮 | 35 |
| niupi | 牛皮 | 14 | xuantie | 玄铁 | 45 |
| shajinshi | 沙金石 | 18 | canjian | 断剑 | 55 |
| tiekuangshi | 铁矿石 | 22 | muzhuan | 墓砖 | 60 |
| zhenzhu | 珍珠 | 120 | shidunang | 尸毒囊 | 70 |
| lianjinzha | 炼金残渣 | 80 | shanzei_lingpai | 山贼令牌 | 150 |

desc 一句风味文案。

### 3.2 药品（新增 type=drug；weight=0，stack=99，tiers=[1,10]）

| id | 名称 | heal | price（买入价） |
|---|---|---|---|
| pingguo | 苹果 | 30 | 8 |
| xiao_yaoji | 小体力药剂 | 80 | 25 |
| da_yaoji | 体力药剂 | 200 | 60 |

schema：`{"name","type":"drug","desc","weight":0,"stack":99,"heal":N,"price":N,"tiers":[1,10]}`。desc 呼应神父台词（战斗中可点击补充体力）。

### 3.3 武器（type=equip；quality 普通，tradeable true，weight 1，stack 1）

atk 曲线（W=武器等级）：`atk = [9+5(W-1), 22+8(W-1)]`。

| id | 名称 | 级W | atk | 耐久 | 获取方式（装备节点加 forge 字段则可打造） |
|---|---|---|---|---|---|
| liecha | 猎叉 | 2 | 14-30 | 250 | 疯鹅掉落：feng_e 节点加第二掉落 `"drop_equip": {"id":"liecha","rate":8}` |
| niupibian | 牛皮鞭 | 4 | 24-46 | 250 | `"forge": {"materials": {"niupi": 4}, "copper": 300}` |
| tiekuangfu | 铁矿斧 | 6 | 34-62 | 300 | `"forge": {"materials": {"tiekuangshi": 5}, "copper": 800}` |
| echijian | 鳄齿剑 | 8 | 44-78 | 300 | `"forge": {"materials": {"eyupi": 3, "xuantie": 2}, "copper": 1800}` |
| xuantiedao | 玄铁刀 | 10 | 54-94 | 350 | `"forge": {"materials": {"xuantie": 5}, "copper": 3200}` |
| xiangyazhang | 象牙杖 | 12 | 64-110 | 350 | 掘墓人掉落：jue_mu_ren 节点加 `"drop_equip": {"id":"xiangyazhang","rate":10}` |
| dahuandao | 大环刀 | 15 | 79-134 | 400 | `"forge": {"materials": {"shanzei_lingpai": 1, "xuantie": 3}, "copper": 6000}` |

怪物节点新增可选字段 `drop_equip`（独立于 drop_item 材料掉落，由代理 B 在 CombatEngine 胜利结算里消费）。

### 3.4 config.json 增补（代理 A）

- `economy` 增加 `"repair_cost_per_point": 2`（修 1 点耐久 2 铜贝）
- `combat` 增加 `"dungeon_kill_goal": 40`、`dungeon_time_limit_sec: 3000`、`dungeon_reward_copper: 20000`、`dungeon_reward_gold: 1`
- `_doc` 里补一句本轮增补说明

## 4. 机制规格（代理 B 实现）

1. **药品使用（战斗外）**：`PlayerCore.use_drug(id) -> String`（""=成功 / "none"=没有该药 / "full"=满血）。items:drug 分类页列出药品（名称×数量 + `[使用]` 链接 `use_drug:<id>`），结果页回 items:drug。
2. **战斗中用药**：战斗页新增 `[药品]` 链接（`combat_drug`）→ 战斗用药页（列出背包中的药 + 数量，`combat_use:<id>`，返回战斗）。使用 = 恢复体力后怪物还击一回合（CombatEngine 新增 `monster_counter(player)`；玩家被击杀则走战败流程——把 `_attack` 里的战败处理提取成 `_handle_defeat()` 复用）。
3. **商店**：soengdim 商人 npc kind 由 flavor 改为 `shop`（代理 B 改 scenes.json？**不**——kind 改动在 scenes.json，属于 A 的文件。**由 A 直接把 soengdim 的 merchant kind 写成 "shop"**，B 只实现 kind=shop 的页面与事件）。商店页：欢迎语 + 三种药（名称/疗效/单价，`buy_drug:<id>:<n>` 买 1 / 买 10）+ 我现有铜贝 + 返回。扣款走 `spend_copper`（自动折兑），不足给商人语气提示页。
4. **铁匠**：titzoengpou 的 smith kind 由 flavor 改为 `smith`（同上由 A 改）。铁匠页：`[修理手持]`（`repair_hand`）+ `[打造装备]`（`forge_page`）+ 返回。修理价 = (耐久上限-当前) × `repair_cost_per_point`，空手/满耐久提示；打造页列出全部带 `forge` 字段的装备：材料够+钱够 → `forge:<id>` 可点（否则灰字显示缺什么），成功后装备实例入包（add_equip），材料按 `remove_stack` 扣除。Rules 增加 `repair_cost(missing: int) -> int` 与 dungeon 相关 getter。
5. **地宫**：
   - 探险官页 `dungeon_try` 改为真实入口：校验等级 5-15 与 `player.dungeon_day != 当日序号`，通过则 `dungeon_day=当日`、`dungeon_kills=0`、`dungeon_deadline = now + dungeon_time_limit_sec`、`goto digung`；失败给原因文案（等级不符/今日已进入过）。
   - 地宫场景页：任务说明 + 击杀进度 `x/40` + 剩余时间 mm:ss + `[挑战抢劫者]`（`fight:qiang_jie_zhe`）+ `[秘密看守]`（`npc:digung:keeper`）+ `[离开地宫]`（`goto:baksingmun`）。
   - 渲染地宫页时若已超时：清空 kills/deadline（dungeon_day 保留，防当日重复进入），给出「限时已到」提示页并送回 baksingmun。
   - 在地宫内战胜 qiang_jie_zhe → `dungeon_kills += 1`；战败走通用战败（回教堂）并清空 kills/deadline。
   - 看守页：kills ≥ 40 → 发奖励（铜贝 20000 + **金贝 1**，金贝首次有来源）、清空 kills/deadline、`EventBus.dungeon_cleared` 信号（新增）；不足则显示进度与剩余时间。
   - PlayerCore 新字段 `dungeon_day:int=-1 / dungeon_kills:int=0 / dungeon_deadline:int=0`，write_to/read_from 带默认值（旧档兼容）。
6. **掉落扩展**：CombatEngine 胜利结算读取 `drop_equip`（命中 → `player.add_equip`，失败降级 add_stack）。
7. **EventBus**：新增 `signal dungeon_cleared(reward_copper: int, reward_gold: int)`；药品/打造等不强制新信号。
8. **self_test 扩展**（`scripts/self_test.gd`）：药品使用（成功/满血/无药）、战斗用药回合并保持胜负判定、商店买药扣款、修理（价格=缺口×单价、满耐久拒绝）、打造（成功扣除材料/材料不足拒绝）、地宫（等级与每日校验、击杀计数、领奖、当日重复进入拒绝、超时踢出）、`drop_equip` 命中路径、npc kind 白名单补 `shop`/`smith`/`dungeon_keeper`。

## 5. 验证要求

- 代理 A：JSON 语法校验 + 自写 python 交叉校验（exits.to 都存在、locked 出口已按表接线、drop_item/drop_equip/forge.materials 引用的 id 都存在、公式数值抽查 ≥5 个怪）。**不要跑 godot self_test**（npc kind 白名单由 B 更新，会误报）。
- 代理 B：`Godot --headless --path . -s scripts/self_test.gd` 必须全绿（用 `"E:/qbb/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"`）；`-- --shot-tour` 走查中把商店/铁匠/地宫/战斗用药页加入 tour 截图。注意 B 可能遇到 A 的数据尚未就位（并行）：机制代码按契约 id 硬编码即可，self_test 里需要数据的用例在数据缺失时允许 SKIP（打印 SKIP 行），最终联调由主进程负责。

## 6. 回报格式（双方）

≤40 行：改动文件清单、新增 id/事件/字段清单、验证命令与输出结论、SKIP/遗留项。**不要贴大段代码**。
