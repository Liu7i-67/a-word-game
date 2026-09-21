# 航海贸易系统 · 契约定书

> 本文件是本轮扩展的唯一契约。分工与文件边界（违反即返工）：
> - **代理 C（世界数据）**：只改 `data/*.json`（新增 `data/world.json`）
> - **代理 D（机制实现）**：只改 `scripts/**`
> id、字段名、公式以本文为准，不得改名。

## 0. 需求背景（对应主进程收到的问题）

1. 打包后市场货物列表触摸滚动异常 → 修复 PageView/ScrollContainer 触摸滚动（§6.1）
2. 市场许多货物无法买卖 → 统一贸易系统：所有港口市场按本地价买卖全部贸易品（§3/§4）
3. 酒保「打听小道消息」：获知某货在某港「最近很抢手」（§5）
4. 大世界港口大同小异 + 地区特产差价：原产地低价买入、航海到高价地区抛售（§2/§3）
5. 多余装备出售渠道：铁匠回炉收购（§7）

## 1. 贸易品（代理 C 写入 data/items.json，type=goods，weight=0，stack=9999，可买卖）

已有贸易品：putaojiu 葡萄酒(26)、ganyouyou 橄榄油(31)。新增 10 种（`buy_price` 即基准价 base_price，`sell_price` 字段不再使用——卖价由定价引擎给出；tiers 按价位：base<60 → [900,450,225]，60–150 → [300,150,50]，>150 → [120,60,20]）：

| id | 名称 | base | 产地（specialty 所在港） |
|---|---|---|---|
| haiyan | 海盐 | 45 | laguzha 拉古扎 |
| taoqi | 陶器 | 60 | yadian 雅典 |
| xianyu | 鳕鱼干 | 70 | risiben 里斯本 |
| shacao | 莎草纸 | 80 | yalishanda 亚历山大 |
| botejiu | 波特酒 | 90 | risiben 里斯本 |
| maopi | 毛皮 | 95 | aerjier 阿尔及尔 |
| dalishi | 大理石 | 110 | masa 马赛 |
| xiangliao | 香料 | 140 | tunisi 突尼斯 |
| xiangshui | 香水 | 260 | masa 马赛 |
| sichou | 丝绸 | 400 | yisitanbao 伊斯坦堡 |

desc 一句风味文案（地中海物产口吻）。

## 2. 港口（代理 C 写入 data/world.json，并按此在 data/scenes.json 各加 1 个场景）

world.json 结构：
```json
{"_doc": "...", "ports": [
  {"id": "venice", "name": "威尼斯", "region": "地中海", "scene": "maatau",
   "specialties": ["putaojiu", "ganyouyou"], "demand_pool": ["sichou", "xiangliao", "xiangshui", "taoqi"]}
]}
```
 Venice 的 scene 是其市场场景 sicoeng？——**venice 的 trade 场景 = sicoeng（既有市场直接接入新定价引擎）**，scene 字段填 sicoeng。其余 9 港各新建 1 个场景（id=港 id，on_map=false，desc 一句当地风情；npcs 固定 3 个）：
- `{"id":"teleporter","name":"传送","kind":"teleport"}`
- `{"id":"barkeep","name":"酒保","kind":"tavern_rumor"}`
- `{"id":"merchant","name":"商人","kind":"trade_market"}`

| port id | 名称 | region | specialties（0.85 折） | demand_pool（每日抽 2 个热门 ×1.8） |
|---|---|---|---|---|
| venice | 威尼斯 | 地中海 | putaojiu, ganyouyou | sichou, xiangliao, xiangshui, taoqi |
| risiben | 里斯本 | 北海 | botejiu, xianyu | sichou, xiangliao, xiangshui, ganyouyou |
| masa | 马赛 | 地中海 | dalishi, xiangshui | botejiu, haiyan, putaojiu, taoqi |
| tunisi | 突尼斯 | 非洲 | xiangliao, shacao | xianyu, maopi, dalishi, ganyouyou |
| yalishanda | 亚历山大 | 非洲 | shacao, taoqi | sichou, xiangshui, xiangliao, putaojiu |
| yadian | 雅典 | 地中海 | taoqi, dalishi | sichou, xiangshui, haiyan, botejiu |
| yisitanbao | 伊斯坦堡 | 地中海 | sichou | xiangliao, maopi, xiangshui, shacao |
| yisitanbuer | 伊斯坦布尔 | 地中海 | maopi, xianyu | sichou, xiangliao, haiyan, taoqi |
| aerjier | 阿尔及尔 | 非洲 | maopi, haiyan | botejiu, taoqi, dalishi, putaojiu |
| laguzha | 拉古扎 | 地中海 | haiyan | sichou, taoqi, xiangshui, xiangliao |

威尼斯的传送入口在 maatau（既有 teleport NPC 行为升级，不改 kind）；既有 4 城门守卫等全部不动。

## 3. 定价引擎（代理 D 新建 scripts/game/trade.gd，class_name Trade）

```gdscript
static func price(good_id: String, port_id: String, day: int) -> int
static func is_hot(good_id: String, port_id: String, day: int) -> bool
```
- `price = round(base × specialty折扣 × hot加成)`：good ∈ port.specialties → ×0.85；`is_hot` → ×1.8；两者可叠加（叠加时 ≈ ×1.53）。
- `is_hot`：以 `hash(str(day) + "#" + port_id)` 为种子的确定型 RandomNumberGenerator（Godot RandomNumberGenerator.seed 可设 int），从该港 demand_pool 抽 2 个（去重）为当日热门；同一天同港结果恒定（情报才可信）。
- 数值全部取自 config（代理 C 写入）：`trade.specialty_discount_pct=85`、`trade.hot_multiplier_pct=180`、`trade.hot_per_port=2`。
- 当日序号复用 `PlayerCore.current_day()`（本地时区 /86400）。

## 4. 市场与买卖事件（代理 D）

- NPC kind `trade_market` → 该港市场页：列出**全部 12 种贸易品**（名称/当前本地单价/热门标记「🔥抢手」），每品 `trade_buy:<good>:<档位>` 与 `trade_sell:<good>:<档位>`（档位取该品 tiers，另加 `:all` 卖出档）；头部显示当前港口名与 region、随身铜贝；返回港口。
- 威尼斯 sicoeng 既有供应商：**保留逐字开场白与既有 buy/sell 事件不改**，仅将成交价切换为 Trade.price(good,"venice",day)（卖价=买价，同港零差价，无套利）。代理 D 在 router 的 `_buy/_sell` 里把价格来源替换为 Trade 引擎（qty 档位行为不变）。
- 跨港利润 = 异地价差（产地 0.85 vs 某港当日热门 1.8），同港同价买卖无利润，符合经济规范。

## 5. 酒保打听（代理 D）

- kind `tavern_rumor` → 页面：「花 20 铜，听酒保讲讲最近的行情」（`rumor` 链接；不买也有返回）。config `economy.rumor_cost=20`（代理 C 写入）。
- `rumor`：扣款（不足给酒保语气提示），从**当日全部港口的热门集合**随机挑 1 条（排除玩家当前所在港），文案固定句式：「酒保（压低声音）：【{货名}】在【{港名}】最近很抢手，去晚了可就赶不上了……」；再附 1 条产地线索（随机热门品但格式同上即可）。情报必须真实（同一 day 的 is_hot）。

## 6. 传送出海（代理 D）

- 传送页（任何港口/码头可用）：全部 10 港列表；当前所在港显示「当前所在」，其余 `[港名(10银)]` 链接 `tp:<index>`。区域行仍保留（地中海/北海/非洲 现已全部实装；北海/东亚/印度洋 文案改为按 region 展示实况——除上述 3 区域外无港口）。
- `tp` 行为：花费 config `teleport.cost_copper=1000`（文案仍写「10银」）经 `spend_copper` 扣款（银行自动折兑）；成功 → `goto` 该港场景 + 「船票花去 1000 铜贝」提示页；钱不够 → 船老板语气提示页。
- 代理 C 在 config teleport 增加 `cost_copper: 1000`（保留 cost_silver=10 仅作展示）。

## 7. 装备回收（代理 C 定价 + 代理 D 实现）

- 代理 C 给 9 件装备补 `price` 字段（基准价值）：hualiwandao1=800、xiaojinsiteng=150、liecha=200、niupibian=500、tiekuangfu=1200、echijian=2600、xuantiedao=4800、xiangyazhang=7000、dahuandao=12000。
- 铁匠页新增 `[出售装备]`（`sell_equip_page`）：列出全部装备实例（名称/耐久/回收价 = round(price × config `economy.equip_sell_ratio_pct`/100)，=40%），每件 `sell_equip:<idx>`；卖出后实例移除（若是手持则先自动卸下）。config 增加 `economy.equip_sell_ratio_pct=40`（代理 C）。

## 8. 滚动修复（代理 D，问题 1）

- `scripts/ui/page_view.gd`：`mouse_filter = Control.MOUSE_FILTER_PASS`（RichTextLabel 不再吞触摸拖动，事件传给外层 ScrollContainer；[url] 点击不受影响）。
- 两块屏的 ScrollContainer：`vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER`（隐藏滚动条、保留触摸滚动，移动端观感）。
- 说明：无真机，最终以用户真机验证为准，代码注释里写明这两处是触摸滚动修复点。

## 9. 验证要求

- **代理 C**：python 交叉校验（world.json 的 specialties/demand_pool/scene 全部存在且 ids 合法；10 新贸易品 tiers 按 §1 规则；9 装备 price 就位；config 新键齐全；scenes.json 新场景 npcs 三个 kind 精确）。不跑 godot。
- **代理 D**：self_test 必须全绿（原用例不许回退），新增用例：定价确定性（同 day 同价；is_hot 随 day 变化用不同 day 断言）、热门折扣叠加公式抽查、情报真实性（rumor 报告的品当日该港必 hot）、跨港买卖利润路径（产地买入→热门港卖出赚差价）、tp 扣费与到达、威尼斯市场旧事件回归、装备回收（价格=40%、手持卖出自动卸下）、滚动配置断言（mouse_filter=PASS、SHOW_NEVER）；shot_tour 补：港口市场页（含🔥标记）、酒保情报页、传送页、装备回收页。SKIP 机制沿用（数据缺失时打印 SKIP）。

## 10. 回报格式（双方）

≤40 行：改动文件、新增 id/事件/字段、验证输出结论、SKIP/遗留。不贴大段代码。
