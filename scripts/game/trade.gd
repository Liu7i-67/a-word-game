class_name Trade
## 航海贸易定价引擎（契约 docs/trade-spec.md §3）。
## price = round(基准价 × 产地折扣 × 热门加成)；热门以 hash("day#port") 为种子的
## 确定型 RNG 从该港 demand_pool 抽取——同一天同一港结果恒定，酒保情报才可信。
## 数值走 config trade.*，缺失时按契约默认值兜底；world.json / 贸易品未就位时
## 各乘数退化为 ×1（价格=基准价），页面与测试据此走 SKIP。

const VENICE := "venice"

## 契约 §1 的 12 种贸易品（前 2 种既有，后 10 种由 data/items.json 扩充提供）
const GOODS: PackedStringArray = [
	"putaojiu", "ganyouyou",
	"haiyan", "taoqi", "xianyu", "shacao", "botejiu", "maopi",
	"dalishi", "xiangliao", "xiangshui", "sichou",
]


# ---------- config 取值（契约 §3，缺省即契约数值） ----------

static func specialty_discount_pct() -> int:
	return int(Rules.section("trade").get("specialty_discount_pct", 85))


static func hot_multiplier_pct() -> int:
	return int(Rules.section("trade").get("hot_multiplier_pct", 180))


static func hot_per_port() -> int:
	return int(Rules.section("trade").get("hot_per_port", 2))


# ---------- 港口查询 ----------

static func port_def(port_id: String) -> Dictionary:
	GameData.ensure_loaded()
	for p: Dictionary in GameData.world_ports:
		if String(p.get("id", "")) == port_id:
			return p
	return {}


static func port_name(port_id: String) -> String:
	return String(port_def(port_id).get("name", port_id))


static func port_scene(port_id: String) -> String:
	return String(port_def(port_id).get("scene", port_id))


## 场景所属港口 id：9 个新港场景 id=港 id（venice 的 trade 场景=sicoeng）；
## 其余老场景（威尼斯城内/地宫等）一律归 venice。world 数据缺失返回 ""。
static func port_at(scene_id: String) -> String:
	GameData.ensure_loaded()
	if GameData.world_ports.is_empty():
		return ""
	for p: Dictionary in GameData.world_ports:
		var pid := String(p.get("id", ""))
		if pid != "" and (pid == scene_id or String(p.get("scene", "")) == scene_id):
			return pid
	return VENICE if not port_def(VENICE).is_empty() else ""


# ---------- 当日热门（确定型随机，契约 §3） ----------

## 当日该港热门品：从 demand_pool 去重抽 hot_per_port 个；数据缺失返回 []
static func hot_goods(port_id: String, day: int) -> Array[String]:
	var pool: Array[String] = []
	for g in port_def(port_id).get("demand_pool", []):
		var gid := String(g)
		if GameData.has_item(gid) and not pool.has(gid):
			pool.append(gid)
	if pool.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(day) + "#" + port_id)
	var picked: Array[String] = []
	var want := mini(hot_per_port(), pool.size())
	var guard := 0
	while picked.size() < want and guard < 1000:
		guard += 1
		var gid := pool[rng.randi() % pool.size()]
		if not picked.has(gid):
			picked.append(gid)
	return picked


static func is_hot(good_id: String, port_id: String, day: int) -> bool:
	return hot_goods(port_id, day).has(good_id)


## 当日全部港口的热门情报池（排除某港，通常为玩家所在港），供酒保挑 2 条
static func rumor_pool(day: int, exclude_port: String) -> Array[Dictionary]:
	GameData.ensure_loaded()
	var out: Array[Dictionary] = []
	for p: Dictionary in GameData.world_ports:
		var pid := String(p.get("id", ""))
		if pid == "" or pid == exclude_port:
			continue
		for gid in hot_goods(pid, day):
			out.append({"good": gid, "port": pid})
	return out


# ---------- 定价（契约 §3：round(基准 × 产地 × 热门)，可叠加 ≈ ×1.53） ----------

static func price(good_id: String, port_id: String, day: int) -> int:
	var base := int(GameData.get_item(good_id).get("buy_price", 0))
	if base <= 0:
		return 0
	var mult := 1.0
	var specialties: Array = port_def(port_id).get("specialties", [])
	if specialties.has(good_id):
		mult *= float(specialty_discount_pct()) / 100.0
	if is_hot(good_id, port_id, day):
		mult *= float(hot_multiplier_pct()) / 100.0
	return int(round(float(base) * mult))


## 买卖档位：数据自带 tiers 优先；缺失时按契约 §1 价位段兜底
static func tiers_for(good_id: String) -> Array:
	var tiers: Array = GameData.get_item(good_id).get("tiers", [])
	if not tiers.is_empty():
		return tiers
	var base := int(GameData.get_item(good_id).get("buy_price", 0))
	if base <= 0:
		return []
	if base < 60:
		return [900, 450, 225]
	if base <= 150:
		return [300, 150, 50]
	return [120, 60, 20]


## 页面用：契约 12 贸易品 ∩ items.json 实际存在的部分（保持契约顺序）
static func trade_goods() -> Array[String]:
	var out: Array[String] = []
	for gid in GOODS:
		if GameData.has_item(gid):
			out.append(gid)
	return out


## world.json + 全部 12 贸易品是否就位（测试 / 页面 SKIP 判据）
static func trade_data_ready() -> bool:
	GameData.ensure_loaded()
	if GameData.world_ports.size() < 2:
		return false
	for gid in GOODS:
		if not GameData.has_item(gid):
			return false
	return true
