# 出海航行 + 区域世界 契约（2026-09-21，主进程裁决已锁定）

目标：航海取代传送成为跨区机制；每个区域有自己的区域地图（地点+特色NPC）；外港怪物等级递进至 L30；
区域铁匠按档位开放装备；旅店恢复生活体力。数值公式沿用 monsters.json _doc 既有公式，装备锚定 L22 既有曲线。

项目根：`E:\qbb\github\a-word-game`。Godot：`E:\qbb\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`。
自测：`--headless --path . -s scripts/self_test.gd`（退出码 0=全过）；截图：`SHOT_DIR=<绝对目录> Godot --path . --audio-driver Dummy -- --shot-tour`。

## 0. 现状速览（代理必读）

- scenes.json：`{_doc, city_map_name, ports(中文名10), regions(海域名5), active_region, scenes[52]}`；scenes 为数组，元素 {id,name,short,on_map,desc,exits[{dir,to,locked?}],npcs[{id,name,kind,lines?/...}],monsters?[{id,count}]}。9 个外港场景全是空壳（teleporter/barkeep/merchant 三 NPC，无 exits 无 monsters）。
- world.json：`{_doc, ports[10]}`，元素 {id,name,region(海域),scene,specialties,demand_pool}。
- monsters.json：`{_doc, monsters}` 为 **dict**（键=id），值 {name,level,hp,atk[a,b],def,exp[a,b],copper[a,b],drop_rate,drop_item,instances}。公式：hp=round(40×L^1.2)、atk=[3+2L,8+3L]、def=round(5+1.5L)、exp=[round(0.8L)+1,4L+5]、copper=[5L,15L+10]、instances=5。现存梯度 L1-22 全在威尼斯周边。
- items.json 装备 18 件（L1-22，17 件 price>0），武器 atk 曲线 ≈[min 5.2L, max 8.9L]（dahuandao L15=79-134、lingzhuzhiren L22=114-196），护甲 xuantiejia L18 def30 slots1。
- 铁匠：`Pages.smith_page(player)` 写死「威尼斯铁匠铺」，在售=全部 price>0 装备；router `_npc` kind=="smith" 进入；`_buy_equip/repair_hand/forge/enhance/gem/sell_equip` 均与位置无关。
- 传送：码头 teleporter NPC → `teleport` 事件 → `teleport_page/_teleport_page_world` → `tp:<idx>` → `_tp`（扣 1000 铜直跳）；另有占位 npc kind=="sail" → `sail` → `sail_page()`。**本轮全部退役，由航海取代。**
- 地图：`map` 事件 → `Pages.city_map()` 永远是威尼斯（用户痛点）。
- 生活体力：PlayerCore.stamina，`spend_stamina` 低于阈值自动吃体力宝（限购 2 个），**无其他恢复手段**；无 stamina 信号（页面重渲染即刷新）。
- CombatEngine：RefCounted 会话，router 持有；`_init(mid, player)` 读 monsters 表；胜利 router `_attack` 检 finished→won；战败走 lose 流程（revive_scene=gaautong 威尼斯）。
- bottom_actions（router）：规则1 战斗中=攻击/攻击术(条件)/药品/撤退。Trade.port_at(scene) 按场景查港。
- GameData（scripts/data/game_data.gd）：static var ports/regions/world_ports；`map_scenes()`（威尼斯城内 on_map）、`city_map_name`、`has_scene/has_monster/get_monster/get_item`、`ensure_loaded()`。
- 页面管线：Pages 产 BBCode；`link(event,label)`/`WIDE_SEP="　·　"`；PageView 行距 14；列表行 3/行折行惯例（ui-opt 契约）；新 kind 页面 npc lines 必须套 {昵称} 替换（flavor 页先例）。
- self_test：`_process`→异步 `_run_all()` 协程，quit 在协程末尾；`check(cond,msg)`；真实点击时序用例须临时置 0 `ui.click_cooldown_ms`。

## 1. 核心裁决（全部写死，代理不得改设计）

### 1.1 区域模型（10 区）

world.json 新增与 ports 平级的 **`regions` 数组**（10 项，顺序=区域地图页顺序）。元素：

```json
{"id":"venice","name":"威尼斯","map_kind":"venice","map_name":"威尼斯城内地图","port_scene":"sicoeng","desc":"…","scenes":[]}
{"id":"laguzha","name":"拉古扎","map_kind":"area","map_name":"拉古扎沿岸地图","port_scene":"laguzha","desc":"…","scenes":["laguzha_haian","laguzha_shanqiu"]}
```

- `map_kind:"venice"`：`map` 事件走既有 city_map（威尼斯一切不变）；`scenes` 留空（区域判定兜底：场景不属于任何区 → 归威尼斯）。
- `map_kind:"area"`：`scenes` = 2 个新野外场景 id（不含港口场景）；区域地图页列出 港口+scenes。
- 特色 NPC 归属：港口场景内（见 1.3），区域地图页从港口场景 npcs 读取特色条目（inn/smith/sailor/unique flavor 各一）。

**区域梯度表**（D1 按此建场景与怪物；场景 id/名/怪级全部锁死）：

| 区 id | 港 | 名 | 野外场景(id:名:怪级) | 区域怪 L | 铁匠装备档（req_level ≤） |
|---|---|---|---|---|---|
| venice | sicoeng | 威尼斯 | —（既有 14 野外场景不变） | 1-22 | 全部（现状） |
| laguzha | laguzha | 拉古扎 | laguzha_haian:拉古扎海岸:11 / laguzha_shanqiu:拉古扎山丘:13 | 10-13 | ≤10 |
| risiben | risiben | 里斯本 | risiben_jiaoqu:里斯本近郊:13 / risiben_haijiao:里斯本海角:15 | 12-15 | ≤12 |
| masa | masa | 马赛 | masa_shidi:马赛石滩:15 / masa_yakuang:马赛崖矿:17 | 14-17 | ≤15 |
| tunisi | tunisi | 突尼斯 | tunisi_luzhou:突尼斯绿洲:17 / tunisi_shamo:突尼斯沙海:19 | 16-19 | ≤17 |
| aerjier | aerjier | 阿尔及尔 | aerjier_haiwan:阿尔及尔海湾:19 / aerjier_yaolei:阿尔及尔旧垒:21 | 18-21 | ≤18 |
| yalishanda | yalishanda | 亚历山大 | yalishanda_shaqiu:亚历山大沙丘:21 / yalishanda_gumu:亚历山大古墓:23 | 20-23 | ≤20 |
| yadian | yadian | 雅典 | yadian_shanlin:雅典山林:23 / yadian_shendian:雅典神殿遗迹:25 | 22-25 | ≤22 |
| yisitanbao | yisitanbao | 伊斯坦堡 | yisitanbao_chengjiao:伊斯坦堡城郊:25 / yisitanbao_yaolei:伊斯坦堡要塞:27 | 24-27 | ≤24（含新 L24） |
| yisitanbuer | yisitanbuer | 伊斯坦布尔 | yisitanbuer_jiaoqu:伊斯坦布尔近郊:27 / yisitanbuer_huanggong:伊斯坦布尔旧皇宫:29 | 26-30 | 全部（含新 L24/L26） |

### 1.2 新场景（18 个，D1）

每区 2 个：港口 ↔ 野外1 ↔ 野外2（野外1 exits 含港口与野外2；野外2 只连野外1；dir 用「南/北/东/西」合理编排）。desc 每场景 2 句风味文案（有地方特色，勿复制 Venice 文案）。on_map=false。每场景挂本区怪 1-2 种 ×instances 5（用 1.4 的新怪）。生活入口：不加（fish/dive 表不变）。

### 1.3 港口场景扩容（D1 改 9 个外港 + 威尼斯 sicoeng 微调）

每个外港场景 npcs 变为（顺序固定）：
1. `{id:"sailor", name:"船主", kind:"sailor"}`（**替换 teleporter 与旧 sail 占位**）
2. `{id:"innkeeper", name:"< regional name，如 旅店老板娘>", kind:"inn"}`，含 `"lines":[…]` 2 句风味台词
3. `{id:"smith", name:"铁匠", kind:"smith", "stock":[装备 id 数组]}`（stock 按 1.1 档表取 items.json 实际 id，**升序 req_level 排列**；vnice 不加 stock=走全量）
4. 保留 barkeep(tavern_rumor) 与 merchant(trade_market)
5. `{id:"<区特色 npc id>", name:"…", kind:"flavor", "lines":[3 句]}` —— 每区 1 个专属风味 NPC（拉古扎吟游诗人/里斯本老水手/马赛采石匠/突尼斯驯鹰人/阿尔及尔退役海盗/亚历山大博物学者/雅典哲学家/伊斯坦堡香料商人/伊斯坦布尔宫廷术士），lines 用第二人称、可含 {昵称} 占位。

威尼斯 sicoeng：teleporter 替换为 sailor；不加 inn/stock（威尼斯城内酒馆已加住店，见 1.7）。

### 1.4 新怪物（24 个，D1）

**区域怪 18**（id 前缀=区 id，命名有地方风味；数值严格按 §0 公式；drop_item 从现有材料/渔获表选 + drop_rate 30-50；每场景 2 种：L=场景标注值与 ±2）：

- laguzha: `laguzha_haidao` 海岸掠袭者 L11 / `laguzha_yejueshu` 山丘野爵猪 L13
- risiben: `risiben_shanzei` 近郊山贼 L13 / `risiben_haiyaokui` 海角鸦魁 L15
- masa: `masa_shijiang` 石滩蟹将 L15 / `masa_yaolang` 崖矿岩狼 L17
- tunisi: `tunisi_tuying` 绿洲土鹰 L17 / `tunisi_shajuan` 沙海沙蜷 L19
- aerjier: `aerjier_haigui` 海湾海魁 L19 / `aerjier_leiwei` 旧垒卫魂 L21
- yalishanda: `yalishanda_shawei` 沙丘蝎卫 L21 / `yalishanda_munaiyi` 古墓木乃伊 L23
- yadian: `yadian_shanhou` 山林石猴 L23 / `yadian_shedian` 神殿蛇斗士 L25
- yisitanbao: `yisitanbao_tieqi` 城郊铁骑 L25 / `yisitanbao_leishi` 要塞雷士 L27
- yisitanbuer: `yisitanbuer Jinwei`→ **id: yisitanbuer_jinwei** 旧皇宫近卫 L27 / `yisitanbuer_huan` 皇宫幻术师 L29

（注意：id 一律 snake_case ASCII；上表若笔误以本行 spells 为准：yisitanbuer_jinwei / yisitanbuer_huan。）

**海怪 6**（航海遭遇池，多一个字段 `"habitat":"sea"`，其余字段同公式）：

- `haiou_qun` 海鸥群 L5 / `anjiao_renyu` 暗礁人鱼 L10 / `shenhai_ju_man` 深海巨鳗 L15
- `youling_fanchuan` 幽灵帆船 L20 / `kelaken_youzai` 克拉肯幼崽 L25 / `fengbao_sairen` 风暴塞壬 L30

掉落主题：渔获/海产（xiaoyu、zhenzhu、haizao、haiyan 等现有物品）。

### 1.5 新装备 4 件（D1，items.json，price>0，weight 8-12，stack 1，desc 有风味）

- `longya_ren` 龙牙刃 L24 atk [124,210] price 42000
- `longlin_jia` 龙鳞甲 L24 def 34 slots 1 price 46000
- `fenghuang_zhang` 凤凰杖 L26 atk [134,228] price 56000
- `shengdian_zhongkai` 圣殿重铠 L26 def 38 slots 1 price 60000

### 1.6 航海机制（E1 引擎 + E2a 路由）

- **船主页**：`sailor` 事件 → `Pages.sailor_page(player)`：列出 10 港（当前港标「当前所在」不可选），每行 `sail_to:<idx>`（idx=GameData.world_ports 下标）+ 船费文案。
- **开航** `sail_to:<idx>`（E2a）：校验 当前在港口场景（Trade.port_at 非空）→ 扣 `Rules.sail_cost()`（不足→船主页 notice）→ 生成海怪：候选=GameData 海怪(habitat=="sea") 中 |level−player.level|≤3，空则取等级最近者，player.rng 随机取一 → `combat = CombatEngine(id, player)`、`combat.at_sea = true`、router 记 `sail_to_port = world_ports[idx]`（会话态，不入存档）。**player.location 保持出发港不变直到胜利**（中途退出游戏=留在出发港，船费已付，可接受）。
- **海战**：`combat.at_sea` 时——`Pages.combat_page` 隐藏撤退链接并显示「海战」标识；`bottom_actions` 规则 1 去掉撤退；`_retreat` 直接渲染 notice「大海上无处可逃，只能迎战！」。
- **胜利抵达**（E2a `_attack` 胜利分支）：先 `player.set_location(目的港 scene)` + needs_save，再渲染 combat_page，notice=「海战获胜！船已靠岸——<港名>。」；随后 combat_reward/combat_leave 既有流程零改动。
- **战败**：既有战败流程不动（复活回威尼斯 gaautong，文案契合「被路过商船救起」——E2b 把 lose_page 文案加一句海战变体）。
- **自动战斗**：零改动自然兼容（胜利页→返回游戏=已抵达的港口场景）。
- **退役**：router 删 `teleport`/`tp`/`sail` 三个 cmd 与 `_tp`/`_teleport` 相关函数；pages 删 `teleport_page/_teleport_page_world/tp_arrival_page/sail_page`（确认无其他引用后）；GameData.ports/regions 字段保留加载（无害）。

### 1.7 旅店（E1 Life 函数 + E2a/E2b 页面）

- `Life.inn_rest(player, cost) -> Dictionary{ok,msg}`：spend_copper 失败→{ok:false,msg:"<房费>铜贝都拿不出来…"}；成功→stamina=max_stamina()、hp 回满（hp_changed.emit）、msg=「你开了间房，美美睡了一觉。生活体力和体力全都回满了！」。
- `Rules.inn_cost()` ← config `economy.inn_cost=100`；`Rules.sail_cost()` ← `economy.sail_cost=1000`。
- 旅店页 `Pages.inn_page(player, npc)`（老板台词套 {昵称} 替换）+ `inn_rest` 事件 + `Pages.inn_result(player, res)`；外港 9 个 + **威尼斯酒馆 zaugun 的 tavern_page 尾部加「住店恢复」链接（inn_rest）**。

### 1.8 区域地图（E1 GameData + E2b 页面 + E2a 路由）

- GameData：`regions_data: Array[Dictionary]`（world.json regions 原样加载）+ `region_of_scene(scene_id) -> Dictionary`（遍历 regions 的 scenes+port_scene；venice 为兜底返回）。
- `map` 事件（E2a）：`region_of_scene(player.location)` → map_kind=="venice" → `Pages.city_map()`（不变）；=="area" → `Pages.region_map(player, region)`。
- `Pages.region_map(player, region)`（E2b）：header(region.map_name) + desc(dim) + 「地点」：港口+scenes 逐个 `goto:<id>`（WIDE_SEP、3/行）+「特色人物」：港口 npcs 中 kind ∈ {sailor,inn,smith} 及有 lines 的 flavor，逐个 `npc:<port_scene>:<npc_id>`（标注身份，如 船主/旅店/铁匠）+ 尾部 `[center] link("worldmap","大世界") [/center]`。
- worldmap_page（E2b 顺带）：每组区域名改链到该区地图？——**不做**（worldmap 保持只读指路，行尾补 dim「在各地港口点『地图』查看当地区域地图」）。

### 1.9 bottom_actions / 商店族

- 规则 1 海战去掉撤退（见 1.6）。
- 铁匠族：外港铁匠经 npc kind=smith 打开 → `_npc` 分支已置 `page_family="smith"`（既有机制）✓；`buy_equip` 事件在 stock 页同样可用（E2b smith 页购买链接 event 不变）。

### 1.10 传送保留（2026-09-21 用户裁决：传送与航海并存，不冲突）

- **传送恢复为原有形态**：码头/港口的「传送师」NPC（kind="teleport"）→ `teleport` 事件 → 传送页 → `tp:<idx>` 扣 `Rules.teleport_cost_copper()`（1000 铜）**安全直达**目的港；航海（1000 铜 + 必遇海战 + 战利品）为其风险备选，两者并存。
- 恢复范围：router 的 `teleport`/`tp` cmd 与 `_tp` 函数、_npc kind=="teleport" 分支；Pages 的 `teleport_page/_teleport_page_world/tp_arrival_page/_is_current_port`（均可从 git HEAD（提交 9de997a）取回原实现，恢复时注明与 sail-region §1.10 的并存关系）。旧 `sail` 占位 NPC/页面**不恢复**（已被真航海取代）。
- 数据：maatau 与 9 个外港场景各补回 `{"id":"teleporter","name":"传送师","kind":"teleport"}`（放在 sailor 之后），原有六 NPC 不动。
- self_test：npc_kinds 白名单加回 "teleport"；shot_tour 补一张传送页截图。
- 文案区分：传送页 dim 注明「传送安全直达；乘船更冒险但海战有战利品」。

## 2. 文件边界（零交集）

| 代理 | 独占文件 |
|---|---|
| D1（波1） | `data/world.json`、`data/scenes.json`、`data/monsters.json`、`data/items.json` |
| E1（波1） | `scripts/data/game_data.gd`、`scripts/game/combat_engine.gd`、`scripts/game/rules.gd`、`data/config.json`、`scripts/life/life.gd`、`scripts/self_test.gd` |
| E2a（波2） | `scripts/game/event_router.gd`、`scripts/ui/game_screen.gd`（如需） |
| E2b（波2） | `scripts/game/pages.gd`、`scripts/dev/shot_tour.gd`、`scripts/self_test.gd`（波1已合并） |

波1 并行期：E1 的自测若因 D1 数据未就位而失败，属「预期并行缺口」，E1 记录不得改 data/*；修缝归 E2b。E1 引擎逻辑须用「构造内存数据/跳过数据依赖」的方式自证（或打 SKIP）。
跨波锁定：E2a/E2b 按 §1.6/§1.7/§1.8 的事件词、函数签名直接实现；D1 按 §1.1-§1.5 的 id 表建数据，禁止改名。

## 3. 验收口径（主进程执行）

1. 边界：git status 只含授权文件。2. 全量 self_test 退出码 0（含 D1 数据硬校验：24 新怪公式逐条、海怪 habitat、区域表完整、装备档位）。3. shot_tour 新走查截图目检：船主页/海战页（无撤退）/抵达 notice/旅店页/区域地图/外港铁匠。4. 抽查：map 事件在威尼斯与外港分流正确；tp/teleport 引用清零。

## 4. 回报格式（每个代理 ≤40 行）

```
DONE|SKIP: <D1|E1|E2a|E2b>
改动文件: <列表>
自测: <命令与退出码；新增用例数>
要点: ≤5 条
遗留/SKIP 项: <无则写 无>
```
