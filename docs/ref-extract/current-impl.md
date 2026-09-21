# 现状与扩展指南（current-impl）

> 盘点时间：2026-09-21，对应版本 v1.0.3（`git log` 末尾）。本文档供主进程做差距分析与派发实现子代理用；
> 只描述「现在是什么样、怎么扩」，不含规划。逐字文案来源标注惯例：文档✅=《游戏设计机制.md》可核对事实，🔍=合理补全。

---

## 1. 架构总览

**一句话**：单场景（`scenes/main/main.tscn`，唯一 tscn）+ 全代码 UI；`PlayerState` 持有全部可变状态，`EventRouter` 把 `[url=事件]` 字符串分发成「改状态 + 产出 BBCode 页面」，`PageView`（RichTextLabel）渲染页面，`SaveManager` 是唯一存档入口（加密 + 校验和 + .bak 回退）。逻辑与数据分离：数值在 `data/config.json`，公式在 `Rules`（纯静态），内容在其余 JSON 表。

```
main.gd（装配：TitleScreen/GameScreen 切换、生命周期存档、--shot-tour、检查更新链路）
 ├─ TitleScreen  ──┐
 ├─ GameScreen   ──┤── 每次交互调 router.handle(event) → 读 router.page 渲染
 │                  │
 │   EventRouter（RefCounted，核心分发器，对应原版超链接主分发）
 │     ├─ PlayerCore（PlayerState autoload：状态 + 全部数值校验，UI 不得直改字段）
 │     ├─ Pages（static BBCode 构建器：页面 = 状态的函数）
 │     ├─ CombatEngine（RefCounted 单场战斗实例，router.combat 持有）
 │     ├─ Trade（static 定价引擎：产地折扣 × 当日热门）
 │     └─ Rules（static 公式 + config 取值）
 ├─ EventBus（autoload，past-tense 信号总线，无状态）
 ├─ SaveManager（autoload，唯一存档读写入口）
 └─ GameManager（autoload，仅 BOOT/TITLE/PLAYING 状态机编排）
```

### 1.1 分层职责（改动时不得越界）

| 层 | 文件 | 职责 | 禁止 |
|---|---|---|---|
| 数据 | `data/*.json` | 全部内容与数值 | 不写逻辑 |
| 数据入口 | `scripts/data/game_data.gd` | static 加载/查询（非 autoload，用前 `ensure_loaded()`） | 不存可变状态 |
| 公式 | `scripts/game/rules.gd` | 公式在这里，数值在 config | 不硬编码数值 |
| 状态 | `scripts/autoload/player_state.gd` | 校验集中地（`spend_copper` 自动银行折兑、`add_stack` 负重/堆叠校验等） | UI 直接改字段 |
| 页面 | `scripts/game/pages.gd`（1133 行） | 全部 BBCode 页面构建 | 页面里改状态 |
| 分发 | `scripts/game/event_router.gd`（932 行） | 事件 → 校验/改状态（经 PlayerCore）→ 生成新页面 | 自建存档读写 |
| UI | `scripts/ui/*.gd` | 渲染 router.page、转发点击、toast、自动战斗按钮 | 直接改游戏状态 |

### 1.2 Autoload 与存档

- project.godot autoload 顺序：`EventBus → SaveManager → PlayerState → GameManager`。
- **存档结构**：`user://save.bin`（`FileAccess.open_encrypted_with_pass`，固定密码 `a-word-game::v1::local-only`），payload = `{"checksum": data.hash(), "data": data}`；`data._version=1`，`_saved_at_unix`；核心是 `data.player` 字典（PlayerCore.write_to/read_from 切片：nickname/gender/level/exp/hp/sin/avatar/copper/gold/bank_silver/bag{id:count}/equips[{id,dur}]/hand/location/welfare_week/dungeon_day/dungeon_kills/dungeon_deadline/exp_buff_left/exp_buff_mult）。旧档缺字段自动取默认值；`_migrate()` 留有版本链注释位。
- **存档时机**：`router.needs_save=true` 的事件在 `GameScreen._after_event()` 统一落盘；另有手动「存档」按钮、Android 暂停（`NOTIFICATION_APPLICATION_PAUSED`）与桌面关闭兜底（main.gd）。
- EventBus 信号清单（全部 past-tense）：`scene_entered / battle_won / battle_lost / enemy_defeated / player_died / weapon_broken / leveled_up / item_obtained / welfare_claimed / dungeon_cleared`。
- GameManager 极薄：只有 `enum State {BOOT,TITLE,PLAYING}` + `enter_state()`。

### 1.3 Pages 与可点击文本机制

- 页面就是 BBCode 字符串；一切可点击元素用 `Pages.link(event, label)` 生成 `[color=链接色][url=事件][font_size=30]文案[/font_size][/url][/color]`（链接色 `ui.link_color`，字号 30 + 行距 14，对齐顶部按钮 58px 触控高度）。
- `PageView`（RichTextLabel，`bbcode_enabled`、`scroll_active=false`、`mouse_filter=PASS`）把 `meta_clicked` 转成 `link_activated(event)` 信号 → GameScreen/TitleScreen 调 `router.handle(event)` → `_render()` 换页（带 0.12s visible_ratio 淡入 + 滚回顶）。
- 点击冷却 250ms（`ui.click_cooldown_ms`）在 UI 层把关；提示走 `_show_toast()`。
- `Pages.esc()` 转义 `[`/`]` 为 `[lb]`/`[rb]` 占位（防文案破坏 BBCode）；`Pages.footer()` 是通用页脚（状态/物品/地图/返回游戏）。
- 输入类事件（如建号名）走 `router.input_mode == "char_name"`：TitleScreen 据此显隐 `LineEdit`，并把输入文本作为 `handle(event, param)` 的第二参传入（目前只有 `create:♂/♀` 一处）。

### 1.4 EventRouter 事件分发模型

`handle(event, param="")`：`event.split(":")` → `cmd/arg/arg2` → 一个大 `match cmd`（60+ 分支）→ 各 `_private()` 处理函数「校验 → 改 PlayerCore → `page = Pages.xxx()` → 需要时 `needs_save = true` / 发 EventBus」。未知 cmd 兜底到 `notice_page("这个入口暂时通向虚空……")`。

事件 URL 约定（新增事件照此命名）：

| 模式 | 例 | 说明 |
|---|---|---|
| `cmd` | `status` / `map` / `attack` | 无参动作 |
| `cmd:arg` | `goto:zaugun` / `fight:bingji` / `use_drug:pingguo` | 单参 |
| `cmd:arg:arg2` | `buy:putaojiu:225` / `trade_sell:sichou:all` / `sell_equip:3` | 数量/下标；`all` 表示全部 |
| `npc:场景id:npcid` | `npc:sicoeng:vendor` | 场景内 NPC 入口，按 kind 二次分发 |

**新增一个事件的完整步骤**（以 `cmd:xxx` 为例）：
1. `pages.gd` 新页面函数：`static func xxx_page(player: PlayerCore, ...) -> String`，可点元素用 `Pages.link("xxx:参数", "文案")`；
2. `event_router.gd` 的 `match` 加分支 `"xxx": _xxx(arg)`，实现 `_xxx()`：校验 → `player` 方法改状态 → `page = Pages.xxx_result(...)` → `needs_save = true`（改状态了就置）→ 有跨场景意义就 `bus.信号.emit(...)`；
3. 入口：把 `link("xxx:...", ...)` 挂到某个页面（场景/NPC 页/物品页等）；
4. `self_test.gd` 加用例（见 §4.7），必要时 `shot_tour.gd` 补截图（见 §4.8）。

NPC 分发链：`_npc(scene_id, npc_id)` 在场景 npcs 里找到该 NPC，按其 `kind` match 到页面。**现有 kind 全集（14 种）**：`flavor`（对白，支持 `{昵称}` 替换）、`welfare`、`church`、`bank`、`casino`、`market`、`teleport`、`sail`（占位）、`dungeon`（探险官）、`shop`、`smith`、`trade_market`、`tavern_rumor`、`dungeon_keeper`。**新增 NPC 功能 = scenes.json 加 npc（新 kind）+ router 的 `_npc` match 加分支 + Pages 加页面 + self_test 的 kind 白名单补名**。

### 1.5 战斗（CombatEngine）

- `CombatEngine.new(monster_id, player)` 从 monsters.json 读属性；`attack_round(player)` 一回合 = 玩家先手（`atk_range()` 随机 − 怪 def）→ 手持武器 `damage_hand()` 耗 1 耐久（可断）→ 怪还手（区间 − 玩家 def）；日志保留最后 4 条。
- 胜利 `_grant_win_rewards`：exp 区间随机 ×`consume_exp_buff()`（加速丹）→ copper 区间 → `drop_rate`% 命中 `drop_item`（装备类掉落 `add_equip` 失败降级 `add_stack`）→ `drop_equip {id,rate}`% 独立判定。
- 战败统一走 `router._handle_defeat()`（普通攻击与战斗中用药共用）：清地宫进度 → 丢 `death_loss(copper)` 铜贝 → 回 `revive_scene`（教堂）半血复活。
- 撤退付费 = 怪等级 ×10；战斗中可 `combat_drug` → `combat_use:<id>`（体力药消耗一回合、怪还手；exp_buff 丹不引还击）。
- **自动战斗**（GameScreen，UI 层实现）：`_auto_run()` 协程每 `ui.auto_tick_ms`(450ms) 模拟真人点击链「fight 首怪 → attack → combat_reward → combat_leave → 再战」；体力 <30%（`combat.auto_stop_hp_pct`）、战败、离开场景、无可战斗对象时自动停；按钮「自动战斗/战斗ing」切换。
- 地宫流程：探险官 `dungeon_try`（等级 5-15 校验 + `dungeon_day` 当日一次）→ 进入 `digung`（超时即踢回北城门并清进度）→ 战胜 `qiang_jie_zhe` 计 `dungeon_kills` → ≥40 向 `keeper` 领奖（20000 铜贝 + 1 金贝，唯一金贝来源）→ 发 `dungeon_cleared`。

### 1.6 航海贸易（Trade 引擎）

- `Trade.price(good, port, day) = round(items.buy_price × 产地0.85 × 当日热门1.8)`（可叠加 ≈×1.53）；当日热门：以 `hash("day#port")` 为种子的确定型 RNG 从该港 `demand_pool` 抽 2 个（同日同港恒定 → 酒保情报可信）。
- `port_at(scene_id)` 反查所在港（9 港场景 id=港 id，venice 的市场场景是既有 `sicoeng`；老场景一律归 venice）。
- 威尼斯既有市场 `_buy/_sell` 价源已切 Trade 引擎（同港零差价无套利）；`_sell_unit_price` 三级：贸易品→引擎价、带 `sell_price` 字段（材料）→固定回收价、兜底→买价 50%。
- 港口三件套 NPC：`trade_market`（12 贸易品本地价 + 🔥抢手标记 + 买卖档位）、`tavern_rumor`（20 铜打听 2 条必真情报、排除当前港）、`teleport`（10 港列表，扣 `teleport.cost_copper`=1000 铜贝，文案仍写「10银」）。
- 数据缺失兜底：`world.json`/贸易品未就位时各乘数退化为 ×1、页面/测试走 SKIP。

### 1.7 UI 层

- **GameScreen**：SafeAreaFrame（安全区避让）→ Margin(28/24/28) → VBox[顶栏（昵称 Lv/体力条 46px/铜贝）→ 导航行（状态/物品/地图/存档/自动战斗，58px 高）→ ScrollContainer(横向禁用、纵向 SHOW_NEVER) > PageView] + toast（底部淡出 Tween）。
- **TitleScreen**：安全区框 → 输入行（LineEdit 在页面区上方，防软键盘遮挡）+ ScrollContainer > PageView；`page_changed` 信号驱动异步更新结果重渲染。
- **SafeAreaFrame**：`DisplayServer.get_display_safe_area()`（窗口像素）经 `get_final_transform().affine_inverse()` 换算回 canvas 坐标求四边 margin；支持 `--sim-insets=左,上,右,下` 命令行模拟与运行时 `set_simulated_insets()`；headless/无刘海恒 0。
- 主题：默认字号 26；橙标题 `#ff9900`、灰注 `#9a9a9a` 致敬原版 CSS。
- **UpdateChecker**：`HTTPRequest` 拉 `api.github.com/repos/{repo}/releases/latest`，取 apk 资产直链；链路 router 发 `update_check_requested` → Main 调 checker → `finished` → `router.apply_update_result()` 回填页面并广播 `page_changed`。

---

## 2. 数据表 schema 与 id 全清单

### 2.1 config.json（全局数值，9 节）

| 节 | 字段 |
|---|---|
| `start` | scene=zaugun, level=1, hp=100, copper/gold/bank_silver/sin=0, weapon=hualiwandao1 |
| `growth` | exp_base=500, exp_step=500, hp_base=100, hp_per_level=20, atk_min_base=5, atk_min_per_level=2, atk_max_base=15, atk_max_per_level=5, def_base=0, def_per_level=1, weight_base=100, weight_per_level=10 |
| `combat` | retreat_cost_per_level=10, death_loss_ratio_pct=10, death_loss_min=1, death_loss_max=5000, revive_ratio_pct=50, revive_scene=gaautong, auto_stop_hp_pct=30, dungeon_kill_goal=40, dungeon_time_limit_sec=3000, dungeon_reward_copper=20000, dungeon_reward_gold=1（另有 dungeon_level_min/max=5/15、dungeon_scene=digung、dungeon_exit_scene=baksingmun、dungeon_monster=qiang_jie_zhe 走 Rules 缺省值，config 里未显式写） |
| `economy` | copper_per_silver=100, welfare_copper=10000, heal_amount=50, confess_reduce=10, casino_bet=200, casino_win=1000, sell_ratio_pct=50, repair_cost_per_point=2, rumor_cost=20, equip_sell_ratio_pct=40 |
| `teleport` | cost_silver=10（展示）, cost_copper=1000（实扣） |
| `trade` | specialty_discount_pct=85, hot_multiplier_pct=180, hot_per_port=2 |
| `ui` | click_cooldown_ms=250, link_color=#3d7edb, auto_tick_ms=450 |
| `gm` | password=676767, exp_pill=shibeijingyandan, exp_pill_count=3, knife=xiaodao, knife_count=1 |
| `update` | repo=Liu7i-67/a-word-game |

### 2.2 story.json（开场剧情）

`title{name,tagline,link}` + `pages[7]{text,link}`（逐字取自设计文档 §11；`story:N` 翻页，`story:99` 进建号）。

### 2.3 items.json（`items` 下 42 条）

字段 schema 按 type：

- **equip**（10 条）：`name/type/desc/req_level/quality/tradeable/weight(1)/atk[min,max]/durability/price(回炉基准)/stack=1`，可选 `forge{materials{id:n}, copper}`。id：`hualiwandao1`(1级9-22/350)、`xiaojinsiteng`(1级4-10/200)、`liecha`(2级14-30/250)、`niupibian`(4级, forge 牛皮×4+300)、`tiekuangfu`(6级, forge 铁矿石×5+800)、`echijian`(8级, forge 鳄鱼皮×3+玄铁×2+1800)、`xuantiedao`(10级, forge 玄铁×5+3200)、`xiangyazhang`(12级64-110/350)、`dahuandao`(15级79-134/400, forge 山贼令牌×1+玄铁×3+6000)、`xiaodao`(GM 彩蛋, 100-1000/不可交易/price=0)。
- **goods · 贸易品**（12 条，weight=0，stack=9999，`buy_price`=基准价，`tiers` 买卖档位）：`putaojiu`(26)、`ganyouyou`(31)、`haiyan`(45)、`taoqi`(60)、`xianyu`(70)、`shacao`(80)、`botejiu`(90)、`maopi`(95)、`dalishi`(110)、`xiangliao`(140)、`xiangshui`(260)、`sichou`(400)。tiers：base<60→[900,450,225]，60–150→[300,150,50]，>150→[120,60,20]。
- **goods · 材料**（16 条，`buy_price`=2×`sell_price`，stack=999，tiers=[]，只卖不买）：`emao`(6)、`langpi`(10)、`haizao`(8)、`niupi`(14)、`shajinshi`(18)、`tiekuangshi`(22)、`duyan`(26)、`xiongdan`(30)、`eyupi`(35)、`xuantie`(45)、`canjian`(55)、`muzhuan`(60)、`shidunang`(70)、`lianjinzha`(80)、`shanzei_lingpai`(150)、`zhenzhu`(120)。（sell_price 值）
- **drug**（4 条，`heal`/`price`/`tiers`，stack=99）：`pingguo`(heal30/8)、`xiao_yaoji`(80/25)、`da_yaoji`(200/60)、`shibeijingyandan`（加速丹：`exp_buff{battles:10,multiplier:10}`，无 heal，不在售）。

### 2.4 monsters.json（`monsters` 下 18 条）

schema：`name/level/hp/atk[min,max]/def/exp[min,max]/copper[min,max]/drop_rate(%) /drop_item/instances(=5)`，可选 `drop_equip{id,rate}`（独立于材料掉落）。
id 全清单（等级）：`bingji`病鸡1、`feng_e`疯鹅2（drop_equip→liecha@8%）、`ye_lang`野狼3、`sha_dao`沙盗4、`gong_niu`公牛5、`hai_yao`海妖触手6、`du_she`毒蛇6、`kuang_dao`矿盗7、`hei_xiong`黑熊8、`shi_mo`石魔9、`jiao_shi_xie`礁石蟹9、`ju_e`巨鳄10、`liu_lang_jian_ke`流浪剑客11、`jue_mu_ren`掘墓人12（drop_equip→xiangyazhang@10%）、`lian_jin_shi_bai_ti`炼金失败体13、`zhao_ze_xing_shi`沼泽行尸14、`shan_zei_tou_mu`山贼头目16、`qiang_jie_zhe`抢劫者8（地宫任务怪，无掉落）。
野外怪生成公式：hp=round(40·L^1.2)、atk=[3+2L,8+3L]、def=round(5+1.5L)、exp=[round(0.8L)+1,4L+5]、copper=[5L,15L+10]。

### 2.5 scenes.json（49 场景）

顶层：`city_map_name`、`ports[10 港名]`、`regions[5 海域]`、`active_region=地中海`、`scenes[]`。
场景 schema：`id/name/short/on_map/desc/exits[{dir,to} 或 {dir,name,locked}] /npcs[{id,name,kind,lines?}] /monsters[{id,count}]`。
- **on_map=true 城内 25 场景**：zaugun 酒馆（出生点）、gwongcoeng 广场、maatau ★码头、sicoeng 市场、soengdim 商店、nganhong 银行、doucoeng 赌场、gaautong 教堂、fukleijyun 福利院、titzoengpou 铁匠铺、wonggung 王宫、gingcaatguk 警察局、jingaujyun 研究院、zyuboudim 珠宝店、faajyun 花园、oicingkiu 爱情桥、soengjipgaai 商业街、geoimankeoi 居民区、zyuzaakkeoi 住宅区、zimsinguk 占星屋、nungcoeng 农场、baksingmun/naamsingmun/dungsingmun/saisingmun 四城门。
- **城外 15 场景**（on_map=false，多数含怪）：nungcoeng1 农场1、coujin 草原、moucoeng 牧场、haitan 海滩、tsienhoi 浅海、ngoanzo 暗礁、kuaangsan 矿山、zamlam 森林、mezai 湿地、hongjoe 荒野、soenmon 实验室、gucyunlei 古村落、zozik 沼泽、hauwaan 后山、digung 地宫（无出口，探险官进入）。
- **9 港口场景**（on_map=false，exits=[]，npcs 固定 teleporter/barkeep/merchant 三件套）：risiben 里斯本、masa 马赛、tunisi 突尼斯、yalishanda 亚历山大、yadian 雅典、yisitanbao 伊斯坦堡、yisitanbuer 伊斯坦布尔、aerjier 阿尔及尔、laguzha 拉古扎。
- 占位 NPC（原版即为占位，统一文案「暂未开放，请耐心等待。」）：授业中介、局长、行政官、指挥官、证婚人、女巫、坚贞石碑、珠宝商、船老板。

### 2.6 world.json（`ports` 下 10 港）

schema：`{id, name, region(地中海/北海/非洲), scene(市场场景id), specialties[](产地0.85折), demand_pool[](每日抽2热门×1.8)}`。
id：venice（scene=sicoeng）、risiben、masa、tunisi、yalishanda、yadian、yisitanbao、yisitanbuer、aerjier、laguzha。specialties 与 demand_pool 的完整矩阵见 `docs/trade-spec.md §2`（数据已按契约落全）。

---

## 3. 新增内容的标准步骤（浓缩）

### 3.1 新增地图/场景
1. `data/scenes.json` 加场景对象（id 唯一、name/short 必填、desc 一两句；城外 `on_map:false`），接入点场景的出口与它**双向互连**（把原 `locked` 出口改成 `{"dir","to"}`）；
2. 需要上怪就在该场景 `monsters` 里挂（并先去 monsters.json 建怪）；
3. 有 NPC 就在 `npcs` 里挂（kind 从 14 种白名单选，新功能则见 3.6）；
4. 若是港口：`data/world.json` 加 port（id=场景 id，给 specialties/demand_pool）；
5. 自测：self_test 的数据完整性会自动校验出口指向、NPC kind 白名单、怪物/材料引用存在性。

### 3.2 新增怪物
`monsters.json` 加条目（按 §2.4 公式算数值，instances=5，drop_item 只放材料）→ 场景 `monsters` 挂 `{"id","count"}`。武器掉落不写 drop_item：固定掉落给该怪加 `"drop_equip": {"id","rate"}`，可打造则给装备加 `forge` 字段（CombatEngine 与 forge_page 自动消费，无需改代码）。

### 3.3 新增物品/装备/药品
`items.json` 按类型 schema 加条目（§2.3）。自动生效点：装备→物品页/装备详情/铁匠回收（要给 `price`）/打造页（有 forge 时）；药品→商店在售（有 heal 时）/物品页使用/战斗用药；贸易品→加入 `Trade.GOODS` 常量数组并挂进某港 specialties/demand_pool 才进跨港体系（威尼斯市场按 `type=goods` 全量展示）。注意：**Trade.GOODS 是硬编码 12 种清单**，新增贸易品要同步改 `trade.gd`。

### 3.4 新增商店/NPC 功能
1. scenes.json 目标场景 npcs 加 `{"id","name","kind":"<新kind>"}`（或复用现有 kind）；
2. router `_npc` match 加分支 → Pages 加页面函数 → 需要动作就加事件（步骤见 §1.4）；
3. self_test 的 `npc_kinds` 白名单补新 kind，加链路用例。

### 3.5 新增任务/日常（参照地宫模式）
PlayerCore 加字段（`dungeon_day/kills/deadline` 即样板：`write_to/read_from` 带默认值保证旧档兼容）→ `current_day()/current_week()` 做每日/每周界 → Rules 加 config getter → router 加入口/进度/领奖事件 → EventBus 加完成信号 → self_test 加「校验/计数/领奖/重复拒绝/超时」五件套用例。

### 3.6 新增数值/公式
数值一律进 `config.json` 对应节（`_doc` 里补一行来源标注），`rules.gd` 加 `static func xxx() -> int` getter（带缺省兜底），调用方只走 Rules。

### 3.7 self_test.gd 组织方式（1305 行，SceneTree 脚本）
- 运行：`Godot --headless --path . -s scripts/self_test.gd`（本机 Godot 在 `E:/qbb/Godot_v4.7.1-stable_win64.exe/..._console.exe`）；退出码 0=全绿。
- 结构：`_run_all()` 顺序调 `_test_xxx()` 分组函数：数据完整性 → 数值公式 → PlayerCore → 战斗 → 事件链路（router）→ 药品/商店 → 战斗用药 → 铁匠 → 地宫 → GM 彩蛋/加速丹 → 检查更新（离线）→ 贸易引擎/链路 → 装备回收 → 自动战斗（真实 UI+定时器，`await` 协程）→ drop_equip → 标题点击路径 → 滚动配置 → 安全区 → 存档往返 → SaveManager。
- 断言只用 `check(cond, "中文名")`；异步等 `await _wait_until(cond, timeout, what)`；**数据未就位时打印 `SKIP: ...` 并 return**（并行开发的容错约定）。
- 加用例：新开 `_test_xxx(player)` 函数挂进 `_run_all()`；router 用例套路 = `EventRouter.new()` + `setup(player, null)` + `player.new_game(...)`（+`rng.seed=42` 定随机）+ `router.handle("事件")` + 断言 page 内容/状态变化。
- 注意：`-s` 模式下 autoload 不在树上，GameScreen/SaveManager 相关用例用 `load("res://scripts/...").new()` 动态加载。

### 3.8 --shot-tour 页面走查
`Godot --path . --audio-driver Dummy -- --shot-tour`，截图存 `SHOT_DIR`（默认 user://shots）。`scripts/dev/shot_tour.gd`：建号「马可波罗」→ 按 01-40 编号遍历标题/剧情/建号/场景/战斗/教堂/福利/银行/赌场/市场/码头/商店/铁匠/地宫/战斗用药/港口市场(🔥)/酒保情报/传送/装备回收；`--sim-insets=0,90,0,48` 时补拍异形屏 35/36。驱动 helper：`_drive()`（标题屏）/`_play()`（游戏屏，router.handle + `_after_event` + visible_ratio=1，绕开点击冷却）；`_shot(name)` 等 4 帧 + `frame_post_draw` 后存 PNG。**加新页面 = 在合适位置插 `_play(game, "事件")` + `await _shot("41_xxx")`**；world 数据缺失段走 `_log("TOUR SKIP: ...")`。另有 `--create-repro` 复现建号点击路径。

---

## 4. 已知遗留问题 / 待验证项

代码内无 TODO/FIXME 注释；以下为文档与代码注释明示的遗留：

1. **真机待验（代码注释明示）**：PageView `mouse_filter=PASS` + 两屏 ScrollContainer `SHOW_NEVER` 的触摸滚动修复「无真机，最终以用户真机验证为准」（page_view.gd / game_screen.gd / title_screen.gd 注释）；SafeAreaFrame 真机安全区换算同理（有 `--sim-insets` 模拟兜底）。
2. **占位功能（原版即占位，文案逐字保留）**：出航 `sail`、授业中介、局长、行政官、指挥官、证婚人、女巫、坚贞石碑、珠宝商、船老板（「暂未开放，请耐心等待」）；README 后续待办：技能表、结婚/证婚、police 局、北海/东亚/印度洋港口、出航海上事件。
3. **CJK 字体内置缺失**：`assets/` 目录为空，当前依赖系统字体回退（README 待办）。
4. **设置菜单缺失**：settings.cfg 与进度存档分离未做；无 BGM/音效（README 待办）。
5. **包名未改**：`com.example.awordgame` 上架前需修改（export_presets.cfg）。
6. **每周/每日界线为推断**（player_state.gd 标🔍）：周=任意 604800s 滚动窗口、日=UTC 86400s 自然日，原版真实界线未知。
7. **GM 彩蛋可无限重复触发**（`gm_pwd_ok` 无冷却/次数限制，测试断言「可重复触发」是预期行为）。
8. **`_is_current_port` 只认威尼斯**（pages.gd：传送页兜底分支，仅 world 缺失时用；world 就位后走 `_teleport_page_world`，实际不会触发）。
9. ** Venice 市场页遍历全部 type=goods**（包括 16 种打怪材料——market_main 按 `buy_price` 会被 Trade.price 返回基准价展示可买；材料 buy_price=2×sell_price 在威尼斯也能买，属主进程裁决「打怪材料不做跨港差价」的副作用，sell 端已用 sell_price 固定价）。
10. **存档密钥硬编码**（save_manager.gd `SAVE_PASS` 常量，注释明示仅防随手改档，严格校验留联机服务端）。
11. **无 TODO 类硬伤**；self_test 与 shot_tour 的 SKIP 分支（world/贸易品/price 字段缺失）当前数据已全部就位，实际不会触发。

---

## 5. Git 状态（2026-09-21 盘点时）

`git status --porcelain`：**工作区干净，无未提交改动**。

`git log --oneline -15`（实际全部 9 条提交）：

```
421911c ci: 版本号同步 v1.0.3
0ce1ab8 feat: 交互优化（链接触控对齐按钮）+ 出售装备连续/批量出售 + 自动战斗
76cb09e ci: 版本号同步 v1.0.2
38088e8 feat: GM彩蛋（福利官暗号 676767：加速丹x3+小刀）+ 标题页检查更新
e10d960 feat: 异形屏安全区适配 + 航海贸易系统
d7a639d ci: release_apk.ps1 一键发布（版本递增+打包+GitHub Release 上传）
74bfa9c feat: 城外野外/药品/铁匠/威尼斯地宫 扩展系统
9d737db ui: 放大间距与字号，适配大屏手机
3ae8ec2 feat: 纵横四海最小可玩复刻（开场建号/威尼斯场景/战斗闭环/经济子系统）
```

其他环境事实：版本 1.0.3（version/code=4）；`scenes/main/main.tscn` 是唯一场景（仅挂 main.gd）；打包走 `scripts/build_apk.ps1`（build.bat 等价）与 `scripts/release_apk.ps1`（版本递增+GitHub Release，依赖不入库的 `env/.env` GITHUB_TOKEN 与 keystore）；`.shots/`、`.shots_sim/` 已有全套 01-40 走查截图（含 35/36 模拟异形屏）。
