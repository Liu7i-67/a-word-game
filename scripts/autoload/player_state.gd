class_name PlayerCore
extends Node
## 玩家可变运行状态（Autoload: PlayerState，state-holder）。
## 数值校验全部集中在此，UI/页面层只调方法不改字段；
## 持久化唯一入口是 SaveManager，本类只提供 write_to/read_from 切片。

signal hp_changed(current: int, maximum: int)
signal copper_changed(value: int)
signal gold_changed(value: int)
signal bank_changed(silver: int)
signal exp_changed(current: int, needed: int)
signal leveled_up(new_level: int)
signal sin_changed(value: int)
signal inventory_changed
signal location_changed(scene_id: String)

var rng := RandomNumberGenerator.new()

var nickname: String = ""
var gender: String = "♂"
var level: int = 1
var exp_cur: int = 0
var hp_cur: int = 100
var sin: int = 0
var avatar: int = 0

var copper: int = 0
var gold: int = 0
var bank_silver: int = 0

## 背包：bag = {item_id: 数量}（可堆叠）；equips = 装备实例 [{id, dur}]；hand = 手持下标（-1 空手）
var bag: Dictionary = {}
var equips: Array[Dictionary] = []
var hand: int = -1

var location: String = ""
var welfare_week: int = -1

## 威尼斯地宫（扩展契约 §4.5）：dungeon_day = 进入过的当日序号（-1 未进过）
var dungeon_day: int = -1
var dungeon_kills: int = 0
var dungeon_deadline: int = 0


func _ready() -> void:
	rng.randomize()


# ---------- 角色创建 / 存档 ----------

func new_game(name_text: String, gen: String) -> void:
	var start := Rules.section("start")
	nickname = name_text
	gender = "♀" if gen == "♀" else "♂"
	level = maxi(int(start.get("level", 1)), 1)
	exp_cur = 0
	hp_cur = int(start.get("hp", 100))
	copper = maxi(int(start.get("copper", 0)), 0)
	gold = maxi(int(start.get("gold", 0)), 0)
	bank_silver = maxi(int(start.get("bank_silver", 0)), 0)
	sin = maxi(int(start.get("sin", 0)), 0)
	avatar = 0 if gender == "♂" else 1
	bag = {}
	equips = []
	hand = -1
	location = String(start.get("scene", "zaugun"))
	if not GameData.has_scene(location):
		location = "zaugun"
	welfare_week = -1
	dungeon_day = -1
	dungeon_kills = 0
	dungeon_deadline = 0
	var weapon_id := String(start.get("weapon", ""))
	if weapon_id != "" and GameData.has_item(weapon_id):
		var idx := add_equip(weapon_id)
		if idx >= 0:
			equip_hand(idx)
	_emit_all()


func write_to(save: Dictionary) -> void:
	save["player"] = {
		"nickname": nickname,
		"gender": gender,
		"level": level,
		"exp": exp_cur,
		"hp": hp_cur,
		"sin": sin,
		"avatar": avatar,
		"copper": copper,
		"gold": gold,
		"bank_silver": bank_silver,
		"bag": bag.duplicate(true),
		"equips": equips.duplicate(true),
		"hand": hand,
		"location": location,
		"welfare_week": welfare_week,
		"dungeon_day": dungeon_day,
		"dungeon_kills": dungeon_kills,
		"dungeon_deadline": dungeon_deadline,
	}


func read_from(save: Dictionary) -> bool:
	var p: Dictionary = save.get("player", {})
	if p.is_empty():
		return false
	nickname = String(p.get("nickname", ""))
	gender = "♀" if String(p.get("gender", "♂")) == "♀" else "♂"
	level = maxi(int(p.get("level", 1)), 1)
	exp_cur = maxi(int(p.get("exp", 0)), 0)
	sin = maxi(int(p.get("sin", 0)), 0)
	avatar = maxi(int(p.get("avatar", 0)), 0)
	copper = maxi(int(p.get("copper", 0)), 0)
	gold = maxi(int(p.get("gold", 0)), 0)
	bank_silver = maxi(int(p.get("bank_silver", 0)), 0)
	bag = {}
	var saved_bag: Dictionary = p.get("bag", {})
	for id: String in saved_bag:
		if GameData.has_item(id):
			bag[id] = maxi(int(saved_bag[id]), 0)
	equips = []
	var saved_equips: Array = p.get("equips", [])
	for inst: Dictionary in saved_equips:
		var id := String(inst.get("id", ""))
		if not GameData.has_item(id):
			continue
		var dur_max := int(GameData.get_item(id).get("durability", 100))
		equips.append({"id": id, "dur": clampi(int(inst.get("dur", dur_max)), 0, dur_max)})
	hand = clampi(int(p.get("hand", -1)), -1, equips.size() - 1)
	location = String(p.get("location", ""))
	if not GameData.has_scene(location):
		location = String(Rules.section("start").get("scene", "zaugun"))
	welfare_week = int(p.get("welfare_week", -1))
	dungeon_day = int(p.get("dungeon_day", -1))
	dungeon_kills = maxi(int(p.get("dungeon_kills", 0)), 0)
	dungeon_deadline = maxi(int(p.get("dungeon_deadline", 0)), 0)
	hp_cur = clampi(int(p.get("hp", max_hp())), 0, max_hp())
	_emit_all()
	return true


# ---------- 派生属性 ----------

func exp_need() -> int:
	return Rules.exp_to_next(level)


func max_hp() -> int:
	return Rules.max_hp(level)


func atk_range() -> Vector2i:
	var r := Rules.base_atk(level)
	var inst := hand_item()
	if not inst.is_empty():
		var wa: Array = GameData.get_item(String(inst.get("id", ""))).get("atk", [0, 0])
		r = Vector2i(r.x + int(wa[0]), r.y + int(wa[1]))
	return r


func defense() -> int:
	return Rules.base_def(level)


func weight() -> int:
	var w := 0
	for id: String in bag:
		w += int(GameData.get_item(id).get("weight", 0)) * int(bag[id])
	for inst in equips:
		w += int(GameData.get_item(String(inst.get("id", ""))).get("weight", 0))
	return w


func weight_cap() -> int:
	return Rules.weight_cap(level)


func hand_item() -> Dictionary:
	if hand < 0 or hand >= equips.size():
		return {}
	return equips[hand]


func item_name(id: String) -> String:
	return String(GameData.get_item(id).get("name", id))


# ---------- 体力 / 经验 / 罪恶 ----------

func heal(amount: int) -> void:
	if amount <= 0:
		return
	hp_cur = mini(hp_cur + amount, max_hp())
	hp_changed.emit(hp_cur, max_hp())


## 返回 true 表示体力归零（战败）
func hurt(amount: int) -> bool:
	if amount <= 0:
		return hp_cur <= 0
	hp_cur = maxi(hp_cur - amount, 0)
	hp_changed.emit(hp_cur, max_hp())
	return hp_cur <= 0


## 返回升级级数
func add_exp(amount: int) -> int:
	if amount <= 0:
		return 0
	exp_cur += amount
	var gained := 0
	while exp_cur >= exp_need():
		exp_cur -= exp_need()
		level += 1
		gained += 1
		hp_cur = max_hp()
		leveled_up.emit(level)
	exp_changed.emit(exp_cur, exp_need())
	if gained > 0:
		hp_changed.emit(hp_cur, max_hp())
	return gained


func add_sin(amount: int) -> void:
	if amount == 0:
		return
	sin = maxi(sin + amount, 0)
	sin_changed.emit(sin)


# ---------- 货币（校验集中地，UI 不得直改） ----------

func add_copper(amount: int) -> void:
	if amount <= 0:
		return
	copper += amount
	copper_changed.emit(copper)


## 消费扣款：随身铜贝不足时按 1银=copper_per_silver 自动从银行折兑（银行职员台词✅）
func spend_copper(amount: int) -> bool:
	if amount <= 0:
		return false
	if copper >= amount:
		copper -= amount
		copper_changed.emit(copper)
		return true
	var per := Rules.copper_per_silver()
	var silver_needed := ceili(float(amount - copper) / float(per))
	if bank_silver >= silver_needed:
		bank_silver -= silver_needed
		copper += silver_needed * per - amount
		bank_changed.emit(bank_silver)
		copper_changed.emit(copper)
		return true
	return false


## 战败等场景的直接扣除（不触发银行折兑），返回实际丢失数
func take_copper(amount: int) -> int:
	var lost := mini(copper, maxi(amount, 0))
	if lost > 0:
		copper -= lost
		copper_changed.emit(copper)
	return lost


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


func bank_deposit(silver: int) -> bool:
	var cost := silver * Rules.copper_per_silver()
	if silver <= 0 or copper < cost:
		return false
	copper -= cost
	bank_silver += silver
	copper_changed.emit(copper)
	bank_changed.emit(bank_silver)
	return true


func bank_withdraw(silver: int) -> bool:
	if silver <= 0 or bank_silver < silver:
		return false
	bank_silver -= silver
	copper += silver * Rules.copper_per_silver()
	bank_changed.emit(bank_silver)
	copper_changed.emit(copper)
	return true


# ---------- 背包 / 装备 ----------

func count_stack(id: String) -> int:
	return int(bag.get(id, 0))


func add_stack(id: String, count: int) -> bool:
	if count <= 0 or not GameData.has_item(id):
		return false
	var def := GameData.get_item(id)
	var per_weight := int(def.get("weight", 0))
	if per_weight > 0 and weight() + per_weight * count > weight_cap():
		return false
	if count_stack(id) + count > int(def.get("stack", 9999)):
		return false
	bag[id] = count_stack(id) + count
	inventory_changed.emit()
	return true


func remove_stack(id: String, count: int) -> bool:
	var cur := count_stack(id)
	if count <= 0 or cur < count:
		return false
	if cur - count <= 0:
		bag.erase(id)
	else:
		bag[id] = cur - count
	inventory_changed.emit()
	return true


## 加入一件装备实例，返回下标（-1 失败）
func add_equip(id: String) -> int:
	var def := GameData.get_item(id)
	if def.is_empty() or String(def.get("type", "")) != "equip":
		return -1
	if weight() + int(def.get("weight", 0)) > weight_cap():
		return -1
	var inst := {"id": id, "dur": int(def.get("durability", 100))}
	equips.append(inst)
	inventory_changed.emit()
	return equips.size() - 1


## 装备上手，返回 "" 成功；"level" 等级不足；"broken" 已损坏
func equip_hand(idx: int) -> String:
	if idx < 0 or idx >= equips.size():
		return "missing"
	var inst := equips[idx]
	var def := GameData.get_item(String(inst.get("id", "")))
	if level < int(def.get("req_level", 1)):
		return "level"
	if int(inst.get("dur", 0)) <= 0:
		return "broken"
	hand = idx
	inventory_changed.emit()
	return ""


func unequip_hand() -> void:
	hand = -1
	inventory_changed.emit()


## 手持武器消耗 1 点耐久，损坏时返回其名字（并移除）
func damage_hand() -> String:
	if hand < 0 or hand >= equips.size():
		return ""
	var inst := equips[hand]
	inst["dur"] = maxi(int(inst.get("dur", 0)) - 1, 0)
	if int(inst["dur"]) <= 0:
		var broke := item_name(String(inst.get("id", "")))
		equips.remove_at(hand)
		hand = -1
		inventory_changed.emit()
		return broke
	inventory_changed.emit()
	return ""


## 手持装备的耐久缺口（空手返回 -1，满耐久返回 0）
func hand_missing_dur() -> int:
	var inst := hand_item()
	if inst.is_empty():
		return -1
	var def := GameData.get_item(String(inst.get("id", "")))
	return maxi(int(def.get("durability", 1)) - int(inst.get("dur", 0)), 0)


## 移除一件装备实例（铁匠回收等），返回被移除的实例（{}=下标非法）。
## 手持件先自动卸下；其后手持下标前移，避免悬空索引。
func sell_equip(idx: int) -> Dictionary:
	if idx < 0 or idx >= equips.size():
		return {}
	var inst := equips[idx]
	equips.remove_at(idx)
	if hand == idx:
		hand = -1
	elif hand > idx:
		hand -= 1
	inventory_changed.emit()
	return inst


## 修理手持装备至满耐久（付款校验由调用方先行完成）
func repair_hand() -> void:
	var inst := hand_item()
	if inst.is_empty():
		return
	var def := GameData.get_item(String(inst.get("id", "")))
	inst["dur"] = int(def.get("durability", 1))
	inventory_changed.emit()


## 使用药品，返回 ""=成功 / "none"=没有该药 / "full"=满血（扩展契约 §4.1）
func use_drug(id: String) -> String:
	var def := GameData.get_item(id)
	if def.is_empty() or String(def.get("type", "")) != "drug" or count_stack(id) <= 0:
		return "none"
	if hp_cur >= max_hp():
		return "full"
	heal(int(def.get("heal", 0)))
	remove_stack(id, 1)
	return ""


# ---------- 位置 / 福利周 ----------

func set_location(scene_id: String) -> void:
	if not GameData.has_scene(scene_id):
		push_warning("PlayerState: 未知场景 %s" % scene_id)
		return
	location = scene_id
	location_changed.emit(location)


## 以 7 天（604800 秒）为一周的周序号（🔍：原版「每周一次」的具体周界未知）
func current_week() -> int:
	return int(floor(Time.get_unix_time_from_system() / 604800.0))


## 以自然日（86400 秒）为界的当日序号（🔍：原版「每天一次」的具体日界未知）
func current_day() -> int:
	return int(floor(Time.get_unix_time_from_system() / 86400.0))


func welfare_claimable() -> bool:
	return welfare_week < current_week()


func mark_welfare_claimed() -> void:
	welfare_week = current_week()


# ---------- 威尼斯地宫（扩展契约 §4.5） ----------

## 申请进入地宫，返回 ""=放行 / "level"=级别不符 / "visited"=当日已进入过
func dungeon_try_enter() -> String:
	var range_lv := Rules.dungeon_level_range()
	if level < range_lv.x or level > range_lv.y:
		return "level"
	if dungeon_day == current_day():
		return "visited"
	dungeon_day = current_day()
	dungeon_kills = 0
	dungeon_deadline = int(Time.get_unix_time_from_system()) + Rules.dungeon_time_limit_sec()
	return ""


func dungeon_expired() -> bool:
	return dungeon_deadline > 0 and int(Time.get_unix_time_from_system()) >= dungeon_deadline


func dungeon_remaining_sec() -> int:
	if dungeon_deadline <= 0:
		return 0
	return maxi(dungeon_deadline - int(Time.get_unix_time_from_system()), 0)


func dungeon_add_kill() -> void:
	dungeon_kills += 1


## 清空本轮进度（dungeon_day 保留，防当日重复进入）
func dungeon_clear_progress() -> void:
	dungeon_kills = 0
	dungeon_deadline = 0


func _emit_all() -> void:
	hp_changed.emit(hp_cur, max_hp())
	copper_changed.emit(copper)
	gold_changed.emit(gold)
	bank_changed.emit(bank_silver)
	exp_changed.emit(exp_cur, exp_need())
	sin_changed.emit(sin)
	inventory_changed.emit()
	if location != "":
		location_changed.emit(location)
