# UI 单手操作优化 + 宝石属性修复 契约（2026-09-21）

主进程裁决已锁定，代理只做本域内实现。所有验证命令、函数签名、事件词表以本文为准。
项目根：`E:\qbb\github\a-word-game`。Godot：`E:\qbb\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`。

## 0. 背景速览

- UI 全代码构建（唯一 tscn），页面=BBCode（Pages 产出，PageView 渲染，`[url=事件]` 由 EventRouter.handle 分发）。
- GameScreen 布局：safe_frame → margin(28/24/28/28) → vbox(sep18)[ 顶栏(name|hp_bar46|copper), 导航行5按钮(状态/物品/地图/存档/自动战斗, 高58), input_row(隐藏), scroll(EXPAND,装PageView) ]，toast 挂 safe_frame 下。
- 玩家状态 PlayerCore（scripts/autoload/player_state.gd）：`atk_range()`=裸身+武器×强化（**无宝石**）、`defense()`=裸身（**无护甲无宝石**）、`armor_def()`、`gem_bonus(){atk,def,agi,hp}`、`max_hp()=Rules.max_hp(level)`（**无宝石 hp**）、`apply_exp_buff(battles,mult)` 现为取 max 不叠加、`exp_buff_left/mult`、信号 `hp_changed/exp_changed(2参)/inventory_changed` 等已存在。
- 战斗引擎 combat_engine.gd：`:103` 伤害额外加 `gem_bonus.atk`；`:131` `pdef = defense()+armor_def()+gem_bonus.def`。
- 商店族事件：`shop / buy_drug / market / buy / sell_page / sell / trade_buy / trade_sell / rumor`；铁匠族：`smith / smith_enhance / smith_gem / sell_equip_page / sell_equip / sell_equip_all / repair_hand / forge_page / forge / alchemy`；战斗中：`attack / skill_cast / combat_drug / retreat / view / combat_reward / combat_leave`；密码盘：`gm_password / gm_pwd:<1-9|clear> / gm_pwd_ok`。
- 宝石：`hongbaoshi{atk:3} / lanbaoshi{def:2} / lvbaoshi{agi:2} / zibaoshi{hp:50}`（data/items.json，type=gem，bonus 字段）。GM 丹 `shibeijingyandan{exp_buff:{battles:10,multiplier:10}}`，config.json `gm.exp_pill_count` 现=3。
- shot_tour（scripts/dev/shot_tour.gd）已拍 01-53（含 09_city_map、11-13 战斗、51_worldmap、53_gem），**未拍 GM 密码盘**；`_play(game,event)` 驱动经 `game._after_event()`。
- 自测：`Godot --headless --path . -s scripts/self_test.gd`，退出码 0=全过。截图：`SHOT_DIR=<绝对目录> Godot --path . --audio-driver Dummy -- --shot-tour`（带窗口跑，headless 截图是黑图）。

## 1. 文件边界（零交集，越界=验收失败）

| 代理 | 独占文件 |
|---|---|
| E1（波1） | `scripts/autoload/player_state.gd`、`scripts/game/combat_engine.gd`、`data/config.json`、`scripts/self_test.gd` |
| E2a（波2） | `scripts/ui/game_screen.gd` |
| E2b（波2） | `scripts/game/pages.gd`、`scripts/game/event_router.gd`、`scripts/self_test.gd`（波1已合并）、`scripts/dev/shot_tour.gd` |

E1 不得改 pages/event_router/game_screen；E2a/E2b 不得改 player_state/combat_engine/config。
E2a 依赖的 `EventRouter.bottom_actions()` 按 §4 签名直接调用（E2b 并行实现之）；E2a 自测可临时 mock 或依赖联调，最终由主进程联调兜底。

## 2. E1：宝石属性并入真实属性 + GM 加速丹叠加

### 2.1 宝石属性并表（单一天真源）

player_state.gd：
- `atk_range()` 返回值改为「裸身 + 武器×强化 + gem_bonus.atk」（区间两端各加同一 gem atk 值），更新注释。
- `defense()` 改为 `Rules.base_def(level) + armor_def() + int(gem_bonus().get("def",0))`。
- `max_hp()` 改为 `Rules.max_hp(level) + maxi(int(gem_bonus().get("hp",0)),0)`。
- `_remove_equip_at()`（:667，装备移除唯一收口）末尾补：`hp_cur = mini(hp_cur, max_hp())` 并 `hp_changed.emit(hp_cur, max_hp())`（卖出/打碎带紫水晶装备后体力不越上限；镶嵌只增上限无需处理）。

combat_engine.gd（防双算）：
- `:103` 删除 `+ maxi(int(player.gem_bonus().get("atk", 0)), 0)`（atk_range 已含）。
- `:131` 改为 `var pdef := player.defense()`。
- `:100` 与 `:131` 附近注释同步（说明攻击/防御口径已并入宝石与护甲）。

self_test.gd：新增用例（沿用 check() 风格，放生活系统/战斗用例附近）：
- 镶嵌红宝石后 `atk_range()` 两端各 +3；卸载场景不测（无卸宝石功能）。
- 穿护甲 + 镶蓝宝石后 `defense() == Rules.base_def(level) + armor_def() + 2`。
- 镶紫水晶后 `max_hp()` +50；卖出（sell_equip）该件后 `hp_cur <= max_hp()` 且 max_hp 回落。
- 现有断言（:194/:232/:240/:1351/:1363/:1380 等）如受新口径影响：修正期望值并在用例消息注明「口径并入」；不得删用例。
- 全量 self_test 退出码 0。

### 2.2 GM 加速丹：单次 10 颗 + 场次叠加

- `data/config.json`：`gm.exp_pill_count` 3 → **10**。
- `apply_exp_buff()` 改为叠加语义：
  ```gdscript
  var had := exp_buff_left > 0
  exp_buff_left += maxi(battles, 0)
  exp_buff_mult = maxi(maxi(exp_buff_mult, 1) if had else 1, maxi(multiplier, 1))
  ```
  （吃 1 颗=10 场，再吃=20 场……倍率保持最高，不动 `consume_exp_buff`。）
- self_test 新增：连 `apply_exp_buff(10,10)` 两次 → `exp_buff_left==20`；`consume_exp_buff()` 一次后 19 且返回 10。

## 3. E2b：地图/密码盘加间距 + bottom_actions 上下文

### 3.1 误触间距（pages.gd，事件词全部不变）

- `city_map()`：每行 4 → **3** 个入口；相邻链接分隔从 `SEP(" . ")` 加宽（如 `　·　` 全角空格包裹，或改用 `[table=3]`+cell 排布）；行间至少空一行或等价间距。验收：截图上相邻可点文本水平净空 ≥ 一个全角字符宽。
- `worldmap_page()`：组内场景名 3 个/行折行，分隔同样加宽。
- `gm_password_page()`：数字键加大——每键 `[url=gm_pwd:N][font_size=40]　N　[/font_size][/url]`（U+3000 填充），键间 ≥2 全角空格，行间空行；清空/确认行同样加宽分隔。验收：截图上 3×3 键盘明显松散、相邻数字净空 ≥80px。
- 实现 free（全角空格或 BBCode table 皆可），以截图目检为准；`PageView` 若需 table 主题项 override 允许改 page_view.gd（唯一例外，需在回报中声明）。

### 3.2 EventRouter 上下文（event_router.gd）

- 新增字段 `var last_cmd: String = ""`：`handle()` split 后首行赋 `last_cmd = cmd`。
- 新增字段 `var page_is_scene := false`：`handle()` 开头置 false；`_goto()` 成功渲染场景页路径置 true（含地宫/传送等所有走 `_goto` 的路径）。
- 新增方法（E2a 按此调用）：
  ```gdscript
  ## 底部固定操作栏上下文；每项 {"label": String, "event": String}，空数组=隐藏。优先级自上而下命中即返回。
  func bottom_actions() -> Array[Dictionary]
  ```
  规则：
  1. `combat != null and not combat.finished`：攻击=attack；攻击术=skill_cast（仅 `player.has_skill("attack") and not combat.skill_used_this_fight`）；药品=combat_drug；撤退=retreat。
  2. `combat != null and combat.finished`：won → [{领取奖励,combat_reward},{返回游戏,combat_leave}]；否则 [{返回游戏,back_game}]。
  3. 商店族 `last_cmd ∈ {shop,buy_drug,market,buy,sell_page,sell,trade_buy,trade_sell,rumor}` → [{商店,shop},{市场,market},{卖货,sell_page}]。
  4. 铁匠族 `last_cmd ∈ {smith,smith_enhance,smith_gem,sell_equip_page,sell_equip,sell_equip_all,repair_hand,forge_page,forge,alchemy}` → [{强化,smith_enhance},{镶嵌,smith_gem},{出售,sell_equip_page}]。
  5. `combat == null and page_is_scene` 且场景有怪（`GameData.get_scene(player.location).monsters`，去重、经 `GameData.has_monster` 过滤，最多 3）→ 每怪 [{挑战·名,fight:<id>}]。
  6. 其余 → 空数组。
- `_drug_used_msg()` exp_buff 分支文案改为报叠加后总量（数值取 `player.exp_buff_left`），例：「你服下了%s，经验×%d 再续 %d 场（叠加后共剩 %d 场）。」
- pages.gd `gm_reward_page()` 补一行 dim 说明：「加速效果可叠加：每颗×10，持续 10 场。」

### 3.3 用例与走查（self_test.gd + shot_tour.gd）

- self_test 新增：战斗中 bottom_actions 含 攻击/撤退 且事件合法；`handle("shop")` 后返回 3 项且 event=shop/market/sell_page；`handle("smith")` 后 3 项；`_goto` 野外场景后首项 event 以 `fight:` 开头；`city_map()` BBCode 含 goto 链接且相邻 url 间存在加宽分隔；`gm_password_page("6")` 含 gm_pwd:1..9 全部 url。依赖真实点击时序的用例把 `ui.click_cooldown_ms` 临时置 0（既有坑）。
- shot_tour 在 17_welfare 后插入：`_play(game,"gm_password")`、按 3 个数字键（如 6/7/6）、`await _shot("17b_gm_pad")`，然后 `_play(game,"back_game")` 回场景继续原流程。

## 4. E2a：GameScreen 底部固定操作栏 + 经验细条（game_screen.gd）

- **顶栏**：name | VBox[ hp_bar(46,原样), xp_bar ] | copper。xp_bar=ProgressBar：高 8、`show_percentage=false`、无文本、EXPAND_FILL、`SIZE_SHRINK_CENTER`；bg 深色 stylebox、fill 金色（#ffd700 系）；`max=exp_need() value=exp_cur`。VBox separation 4-6。连接 `_player.exp_changed` 刷新；`_refresh_topbar()` 一并更新。
- **删顶部导航行**；底部新增固定区（vbox 末尾、scroll 之后）：VBox `_bottom_box`[ `_ctx_row`(HBox,可隐藏), `_nav_row`(HBox) ]，separation 与按钮高 58、按钮 EXPAND_FILL 均沿用现值。
- `_nav_row`：状态/物品/地图→`_on_menu`（MENU_EVENTS 不变）+ 存档→`_on_manual_save` + 自动战斗→`_on_auto_toggle`（`_auto_btn` 引用/文案切换逻辑原样平移）。
- `_ctx_row`：每次 `_after_event()` 重建——清空子节点（`queue_free`），按 `_router.bottom_actions()` 生成 Button，`pressed.connect(_router.handle.bind(event))` 后走同一 `_after_event` 管线（复用 `_on_link` 的冷却逻辑：统一走一个 `_dispatch(event)` 帮助函数，含 `_too_fast()` 判定）；空数组时整行隐藏。
- scroll 保持 EXPAND_FILL 与滚动配置；input_row 位置不变；toast 不动；`_auto_run()` 逻辑不动。
- 单文件交付，不碰其他文件；若 `bottom_actions()` 未就位导致无法自测，打印 SKIP 并交主进程联调。

## 5. 回报格式（每个代理 ≤40 行）

```
DONE|SKIP: <E1|E2a|E2b>
改动文件: <列表>
自测: self_test 退出码 X（新增用例 N 条）
要点: <关键实现决策 ≤5 条>
遗留/SKIP 项: <无则写 无>
```
