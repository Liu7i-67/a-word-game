# plan-v2：纵横四海内容补全契约（参考 gitee zhsh 仓库）

> 三方并行派发契约：D1 数据层 / E1 引擎层 / E2 UI 层。本文件是唯一接口真相源，实现与本文件冲突时以本文件为准；
> 执行中发现契约缺陷，**回报主进程裁决，不得自行偏离**。标注惯例：✅=zhsh 仓库可确证原文，🔍=合理推断补全。

## 0. 范围总览（本期做什么）

| 域 | 内容 | 依据 |
|---|---|---|
| 大世界版图 | 新增 废弃堡垒/废墟/矿洞 3 野外区域 + 7 新怪 + 大世界地图页 | ✅ excel 51×51 蓝本 |
| 物品补全 | 20 件原版物品（含 2 武器 2 护甲）全量文案 + 宝石/鱼/农产品 | ✅ stuff 表原文 |
| 装备词条 | 护甲槽、品质 6 档、敏捷、幸运一击、毒抗、宝石插槽、强化绑定 | ✅ models 字段 |
| 生活系统 | 体力/负重/打坐/钓鱼/种田/潜水/引路蜂/改名卡/buff 卡片 | ✅ 物品文案硬证据 |
| 战斗扩展 | 士气(连胜)、护甲减伤、闪避、毒伤、攻击术技能 | ✅ 七件套同构 🔍公式 |
| NPC/任务 | 酒馆 7 人卡+对话、安德鲁试炼/西利亚海皇 2 任务链、奥布帕斯每日谜语、实验室炼金助手、福利院预约礼包 | ✅ bio 原文 🔍玩法 |

不动：贸易体系、赌场、银行、地宫、GM 彩蛋、开场剧情、存档加密、UI 框架。存档不升 `_version`（全部新字段 read_from 带默认值兼容旧档）。

## 1. 文件边界（越界即事故）

| 代理 | 可写 | 禁写 |
|---|---|---|
| D1 | `data/items.json` `data/monsters.json` `data/scenes.json` `data/config.json` | 其余一切（尤其 scripts/、self_test） |
| E1 | `scripts/state/player_state.gd` `scripts/game/rules.gd` `scripts/combat/engine.gd` `scripts/data/game_data.gd` 新增 `scripts/life/life.gd` | `data/*.json`、`scripts/game/pages.gd`、`scripts/game/event_router.gd`、`scripts/ui/*`、`scripts/self_test.gd`、`scripts/dev/*` |
| E2 | `scripts/game/pages.gd` `scripts/game/event_router.gd` `scripts/ui/game_screen.gd` `scripts/ui/page_view.gd` `scripts/self_test.gd` `scripts/dev/shot_tour.gd` 新增页面函数均在 pages.gd 内 | `data/*.json`、E1 全部文件（只能按 §4 签名调用） |

三方都必读：本项目 `.agents/skills/godot-word-game/SKILL.md`（GDScript 硬规则）、`docs/ref-extract/current-impl.md`、`docs/ref-extract/01-maps.md`、`03-items-stuff.md`、`04-npcs-quests.md`、`05-mechanics.md`、本文件。

## 2. 数据契约（D1 落地，E1/E2 按此消费）

### 2.1 items.json 新 schema

- **equip 增加可选字段**：`slot`（`"weapon"`|"armor"，缺省 `"weapon"` 兼容旧数据）；armor 用 `def`（替代 atk）；词条可选 `agility/lucky/poison_res/slots`(int 宝石槽数)；强化后运行时置 `tradeable:false`（数据表不预置）。`quality` 1-6：普通/精良/稀有/完美/史诗/传奇。
- **新 type=`item`**（功能道具，stack=99，weight=1 除注明）：公共字段 `name/type/desc/price/tradeable/weight`，效果字段 `effect`（对象）：
  - `{"kind":"stamina","value":N}`（曲奇饼3000/火龙汤圆500/奶瓶8000/体力宝80000）
  - `{"kind":"heal","value":200}`（牛肉馅饼——也可直接复用 drug，裁决：牛肉馅饼=drug 带 heal 200）
  - `{"kind":"exp_buff","hours":1,"multiplier":2.0}`（双倍经验卡）；`{"kind":"clear_buff"}`（还原卡）
  - `{"kind":"weight","value":50}`（乾坤袋，weight=0，stack=20）；`{"kind":"rename","req_level":30}`（改名卡）
  - `{"kind":"teleport_wild"}`（引路蜂，weight=0，tradeable:false ✅）
  - `{"kind":"gift"}`（全服预约礼包）；`{"kind":"skill","skill":"attack"}`（技能书-攻击术）
  - `{"kind":"meditate_tool","req_level":10}`（野球草人，非消耗：使用=学习持有，bag 中标记）
  - `{"kind":"bait"}`（小鱼活饵）；`{"kind":"seed"}`（牧草种子）
- **新 type=`gem`**：`bonus:{"atk":N}` 或 def/agi/hp（红宝石atk3/蓝宝石def2/绿宝石agi2/紫水晶hp50），stack=20，price 200-600。
- **鱼/农产品=goods 材料**（sell_price，只卖不买 tiers=[]）：xiaoyu6/daiyu12/zhangyu25/jinqiangyu60/mucao20；海皇碎片 haihuang_suipian（type=item，effect `{"kind":"quest_item"}`，tradeable:false，不可卖不可用）。
- 新增 20 件 id 锁定：`changjian 长剑`(equip L1 2-5 agi1 price30✅文案)、`duanchui 短锤`(L2 3-4 agi1 price50)、`piyaodai 皮腰带`(armor L1 def1 agi1 lucky1 price30)、`cuzhitongkui 粗制铜盔`(armor L4 def1 agi1 lucky1 poison_res1 slots1 price120)、`niurouxianbing`(drug heal200 price20)、`quqibing`(price150)、`tili_bao`(price0 不可交易 limit2)、`huolong_tangyuan`(price40)、`naiping`(price600)、`shuangbei_jingyanka`(price0 不可交易)、`huanyuan_ka`(price0 不可交易)、`qiankun_dai`(price800)、`yeqiu_caoren`(price1500)、`gaiming_ka`(price2000)、`jineng_shu`(price0 任务奖励不可交易)、`longquanshui`(price0 仅兑换不可交易)、`mucao_zhongzi`(price10)、`xiaoyu_huoer`(price30)、`yinlu_feng`(price300)、`yufu_libao`(price0 福利院领取不可交易)。
- 商店在售：商店页现有逻辑按 heal>0 过滤 drug——**扩展为：有 price 且 price>0 且非任务/绑定物品均在商店/铁匠在售**（E2 改过滤，D1 只管数据）。
- 获取途径：tili_bao/shuangbei_jingyanka/huanyuan_ka/jineng_shu/longquanshui/yufu_libao 不进商店（见 §5 玩法）；宝石：炼金助手兑换 + 矿洞怪 drop_item；野球草人：商店 + 废墟怪掉落。

### 2.2 monsters.json

- 新怪 7 只（数值按现有公式 `hp=round(40·L^1.2)` 等，instances=5；名称可微调、等级带锁定）：
  - 矿洞 `kuongdung`：`kuangshu` 矿鼠 L8、`duwu_bianfu` 毒雾蝙蝠 L11（`poison:10`）
  - 废墟 `feizoi`：`feixu_kulou` 废墟骷髅 L13、`anying_wuling` 暗影亡灵 L16
  - 堡垒 `biltou`：`baolei_shouwei` 堡垒守卫 L18、`hei_an_qishi` 黑暗骑士 L20、`baolei_lingzhu` 堡垒领主 L22（drop_equip 顶级新装备@12%）
- 现有 `du_she` 加 `poison:8`。poison=命中后附加固定毒伤（🔍 E1 结算，见 §4.2）。
- drop_item 新材料：矿洞怪掉宝石（kuangshu→lanbaoshi@6%、duwu_bianfu→lvbaoshi@6%）、废墟怪掉 yeqiu_caoren@5%（anying_wuling→zibaoshi@5%）、堡垒怪掉 tili_bao@5%。

### 2.3 scenes.json

- 新场景 3 个（城外 on_map=false，id 锁定粤语拼风格）：`biltou 废弃堡垒`、`feizoi 废墟`、`kuongdung 矿洞`（desc 各 2 句，融入大世界氛围：堡垒=北方军事废墟群、废墟=东门旧城残骸、矿洞=矿山深处迷宫走廊）。出口双向接线：矿山 kuaangsan↔kuongdung、荒野 hongjoe 或东城门外首环↔feizoi、feizoi↔biltou（D1 读现有拓扑选最顺接点）。
- 农场 `nungcoeng`、海滩 `haitan`、浅海 `tsienhoi`、暗礁 `ngoanzo` 的 desc 各补一句玩法指引（种田/钓鱼/潜水，不新增 npc）。
- 酒馆 `zaugun` npcs 追加 7 人（✅ bio 原文入 lines，id 锁定）：
  `boss` 老板 kind=`tavern`、`deluoxi` 德罗西 kind=`circus`、`andedalu` 安德鲁 kind=`trainer`、`lusi` 露丝 kind=`flavor`（对白 2-3 条）、`xiliya` 西利亚 kind=`siren`、`aobupasi` 奥布帕斯 kind=`riddle`（怪博士不在酒馆挂，见下）
- 实验室 `soenmon` 挂 `zhushou`「博士的助手」kind=`alchemist`（怪博士本体失踪于实验室深处，文案暗示）。
- 酒馆原 barkeep 保留不动。

### 2.4 config.json 新节（数值锁定，E1 写 Rules getter 带缺省兜底）

```json
"life": {
  "stamina_max": 1000, "stamina_per_level": 50,
  "meditate_stamina": 100, "meditate_exp_per_level": 20,
  "fish_stamina": 30, "dive_stamina": 40, "farm_stamina": 20,
  "farm_plots": 4, "farm_grow_sec": 600, "farm_harvest_count": 3,
  "auto_stamina_pct": 50, "tili_bao_limit": 2,
  "fish_scenes": ["haitan","tsienhoi","ngoanzo","maatau"],
  "dive_scenes": ["tsienhoi","ngoanzo"],
  "fish_table": [{"id":"xiaoyu","w":45},{"id":"daiyu","w":30},{"id":"zhangyu","w":17},{"id":"jinqiangyu","w":6},{"id":"xiaoyu_huoer","w":2}],
  "fish_table_bait": [{"id":"daiyu","w":30},{"id":"zhangyu","w":30},{"id":"jinqiangyu","w":28},{"id":"xiaoyu_huoer","w":10},{"id":"zhenzhu","w":2}],
  "dive_table": [{"id":"nothing","w":50},{"id":"xiaoyu","w":20},{"id":"zhenzhu","w":20},{"id":"monster:hai_yao","w":7},{"id":"haihuang_suipian","w":3}]
},
"smith": { "enhance_max": 7, "enhance_copper": 200,
  "alchemy": [ {"give":{"xuantie":2,"shajinshi":3,"copper":500},"get":{"id":"longquanshui","n":1}},
               {"give":{"canjian":1,"lianjinzha":2,"copper":300},"get":{"id":"hongbaoshi","n":1}},
               {"give":{"duyan":2,"copper":300},"get":{"id":"lanbaoshi","n":1}},
               {"give":{"zhenzhu":1,"copper":200},"get":{"id":"zibaoshi","n":1}} ] },
"quest": { "andrew_kills": 10, "andrew_reward_copper": 1000,
  "siren_shards": 3, "siren_reward": {"longquanshui":3,"shuangbei_jingyanka":1},
  "riddle_reward_copper": 500,
  "riddles": [ {"q":"有头无颈，有眼无眉，无脚能行，有翅难飞。（打一动物）","a":"鱼"},
               {"q":"白天草里住，晚上空中游，金光闪闪动，小尾灯一盏。（打一昆虫）","a":"萤火虫"},
               {"q":"小小诸葛亮，独坐军中帐，摆下八卦阵，专捉飞来将。（打一动物）","a":"蜘蛛"},
               {"q":"一物生来强，每天织网忙，织完静静坐，专等蚊虫撞。（打一动物）","a":"蜘蛛"},
               {"q":"背黑肚白， couch 一声跳下海。（打一动物）","a":"企鹅"} ] },
"combat 新增字段（并入现有 combat 节）": { "momentum_max": 10, "momentum_atk_pct_per": 1,
  "dodge_pct_per_agi": 1, "dodge_pct_max": 20, "lucky_pct_per": 1, "lucky_mult_pct": 200,
  "skill_stamina": 50, "skill_mult_pct": 150 }
```

（谜语第 5 条 D1 重写一条通顺的，上面占位勿照抄「couch」。w=权重%，各表合计须=100。）

## 3. id 分配（事件/新 kind 全集，E2 实现，D1 据此写指引文案）

新 kind：`tavern`(酒馆主页：露丝打赏/情报入口/艺人八卦)、`circus`(德罗西：动物皮高价收购=emao/langpi 120%价+马戏团八卦)、`alchemist`(炼金兑换，按 config.smith.alchemy 列表)、`trainer`(安德鲁：试炼任务+技能书学习)、`siren`(西利亚：海皇碎片任务+潜水指引)、`riddle`(奥布帕斯每日谜语)。

新事件 cmd：`use_item:<id>`(通用使用，保留 use_drug 兼容)、`meditate`、`fish`、`farm_plant:<slot>`、`farm_harvest`、`dive`、`smith_enhance`、`smith_gem`、`worldmap`、`quest_andrew`(accept/claim 用 arg)、`quest_siren`、`riddle:<n>`、`skill_cast`(战斗中)、`gift_claim`、`rename`(input_mode="rename")。goto/attack/npc 等既有事件不变。

## 4. 引擎契约（E1 实现，签名锁定；E2 只按签名调用）

### 4.1 PlayerCore（player_state.gd）新增字段（全部进 write_to/read_from，缺省默认值）

`stamina:int`、`weight_bonus:int`(乾坤袋 effect weight +50 累加至此，体力无 bonus 字段)、`equips 条目扩展 {id,dur,gems:Array[String],enhance:int,bound:bool}`、`armor_idx:int`(-1 未穿，指向 equips 下标)、`buffs:Array[{kind,until_unix,mult}]`、`skills:Array[String]`、`streak:int`、`momentum:int`、`quest_andrew:{state,kills,day}`、`quest_siren:{shards,claimed}`、`riddle_day:int`、`farm_plots:Array[Dictionary]`(长度=farm_plots，元素 `{seed_id,planted_unix}` 或 `{}`)、`gift_claimed:bool`。

新增方法（签名锁定）：
- `spend_stamina(n:int)->bool`（不足返回 false；成功后 `_auto_stamina_drink()` 检查 <50% 自动吃奶瓶/体力宝）
- `gain_stamina(n:int)->void`
- `weight_max()->int`（growth.weight_base + level×per + weight_bonus）；`weight_used()->int`（遍历 bag×weight + equips）
- `add_time_buff(kind:String, hours:float, mult:float)->void`；`clear_buffs()->void`；`exp_mult()->float`（max(场次制 exp_buff_mult 若有剩余, 时间制 mult 若未过期)，默认 1.0）
- `equip_armor(idx:int)->bool` / `unequip_armor()->void`；`armor_def()->int`（含耐久>0 校验）；`total_agility()->int`（基础 1 + 成长？裁决：基础 1+level×0 保守=1+装备 agi 和+绿宝石）；`total_lucky()->int`；`total_poison_res()->int`；`gem_bonus()->Dictionary{atk,def,agi,hp}`
- `enhance_equip(idx:int)->Dictionary`（校验龙泉水×1+copper≥enhance_copper+enhance<max；成功：enhance+1、atk×(1+enhance×5%)、bound=true、tradeable 置 false；返回 `{ok, msg}`）
- `socket_gem(equip_idx:int, gem_id:String)->Dictionary`（校验 slots 余量；宝石入 gems 数组并扣包）
- `bump_streak()->void`(streak+1, momentum=min(max,+1))；`reset_streak()->void`(归零)
- `learn_skill(s:String)->bool`；`has_skill(s:String)->bool`
- `plant_plot(i:int, seed_id:String, now:int)->Dictionary`；`harvest_plot(i:int, now:int)->Dictionary{ok,msg,gain}`
- `rename(nick:String)->bool`（level≥req_level 校验放 router）

### 4.2 CombatEngine（engine.gd）改动

- 玩家伤害 = (atk_range + gem atk) × (1+momentum×momentum_atk_pct_per/100) − 怪 def；幸运一击：概率 total_lucky×lucky_pct_per%，触发 ×lucky_mult_pct/100（日志标注「幸运一击！」）。
- 闪避：怪命中概率 = 100% − total_agility×dodge_pct_per_agi%（上限 dodge_pct_max）；未命中日志「你灵巧地闪开了」。
- 玩家 def = 基础 def + armor_def + gem def；怪命中后若 `poison>0`：附加毒伤 max(0, poison − total_poison_res)，日志标注。
- `cast_skill(player)->Dictionary{ok,msg}`：has_skill("attack") 且本场未用且 spend_stamina(skill_stamina)→额外 1.5× 攻击一次。`skill_used_this_fight` 标记。
- 胜利：exp × exp_mult()（现有 consume_exp_buff 场次制保留，取大）；`bump_streak()`；战败/撤退 `reset_streak()`。

### 4.3 life.gd（新增，RefCounted 纯静态）

- `meditate(player)->Dictionary{ok,msg,exp}`（校验 yeqiu_caoren 持有+level≥10+spend_stamina；exp=level×meditate_exp_per_level×exp_mult）
- `fish(player, use_bait:bool)->Dictionary{ok,msg,item_id}`（spend_stamina；use_bait 扣 xiaoyu_huoer×1；按 fish_table 权重抽）
- `dive(player)->Dictionary{ok,msg,item_id|monster_id}`（spend_stamina；抽 dive_table；monster:前缀=触发战斗，返回给 router 起 CombatEngine）
- 加载 game_data 用 `ensure_loaded()` 惯例。

### 4.4 Rules（rules.gd）

为 §2.4 每个数值加 `static func` getter（`life_stamina_max()` 风格，缺省兜底写死与 config 同值），fish/dive/alchemy 表 getter 返回 Array。调用方禁直接读 config。

## 5. 玩法裁决（🔍 推断项，实现照此，文案可润色）

1. **体力**：仅生活玩法（打坐/钓鱼/种田/潜水/攻击术）消耗，战斗不耗；不自然恢复，靠食物；<50% 且包内有奶瓶/体力宝时自动食用（限持：tili_bao bag 计数 ≤2，buy/gift 入包时校验）。
2. **打坐**：任意无怪场景入口（场景页条件显示）；每击 100 体力=即时结算，可连点。
3. **钓鱼**：fish_scenes 场景入口；可选「用活饵」；即时结算。种田：nungcoeng 4 块地，种→600s 成熟→收获 mucao×3+50% 概率返还种子。
4. **潜水**：dive_scenes 入口；抽 dive_table，`nothing` 出安慰文案；海皇碎片集 3 交西利亚换 longquanshui×3+shuangbei_jingyanka×1。
5. **安德鲁试炼**：接受后累计击杀任意野外怪 10 只（dungeon 不计）→ 领 jineng_shu×1+1000 铜；每日可重接（day 轮换，参照 dungeon_day）。技能书使用→learn_skill("attack")。
6. **奥布帕斯谜语**：每日 1 次（riddle_day），从 riddles 轮换取题，答对 500 铜（答错无惩罚可再猜）。
7. **预约礼包**：福利院新入口 gift_claim 一次性领取：yufu_libao×1；打开得 copper×2000+naiping×2+shuangbei_jingyanka×1+huanyuan_ka×1+qiankun_dai×1（gift 效果子表写在 effect 里：`{"kind":"gift","contents":{"copper":2000,"naiping":2,...}}`——D1 落数据，E2/E1 读 contents）。
8. **改名**：物品页对 gaiming_ka 出「使用」→ input_mode="rename" → 校验 level≥30 → 改昵称。
9. **引路蜂**：使用→免费传送列表（全部 on_map=false 野外场景，不含地宫与港口）。
10. **德罗西**：马戏团八卦（flavor）+ 动物皮收购（emao/langpi 按卖价 120%，事件走 router 临时价）。
11. **大世界地图页**：`map` 页脚新增「大世界」→ worldmap 页：按分区（城区/矿山矿洞/废墟堡垒/农场海岸）列全部地点，「前往」=goto（城内免费、野外免费步行到达语义——仅展示已接通场景，传送仍走码头 teleport 收费体系，worldmap 的前往只对**相邻可达**场景显示，避免变相免费传送。简化裁决：worldmap 纯展示+说明文案，不放前往按钮，避免破坏经济）。→ 最终裁决：**worldmap 只读展示**。
12. **品质颜色**：1-6 = 白/绿/蓝/紫/橙/红，装备与宝石名称着色（Pages 层常量，E2 实现）。

## 6. 验收标准（主进程执行）

1. `Godot --headless --path . -s scripts/self_test.gd` 退出码 0（E2 负责新用例：生活系统五件套、词条/强化/宝石、任务链、谜语、存档往返含新字段、旧档兼容=旧 payload 无新字段可读）。
2. `-- --shot-tour` 新增截图 ≥8 张（酒馆七人/炼金/打坐/钓鱼/种田/潜水/大世界/强化宝石）无报错。
3. 经济防刷自查：无「买<卖」套利、礼包/任务奖励不可重复领取、绑定物品不可卖不可交易。
4. 数值全部走 Rules getter；config._doc 补来源标注（✅/🔍）。
