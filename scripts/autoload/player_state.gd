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

## 经验加速丹 buff：剩余场次数 + 生效倍率（战斗胜利结算时消耗 1 场次）
var exp_buff_left: int = 0
var exp_buff_mult: int = 10

## ---------- 生活系统（契约 plan-v2 §4.1） ----------

## 生活玩法专用体力（打坐/钓鱼/种田/潜水/攻击术消耗；不自然恢复，靠食物）
var stamina: int = 1000
## 乾坤袋 effect weight +50 累加至此（可叠加）
var weight_bonus: int = 0
## 装备运行时形状 {id, dur, gems:Array[String], enhance:int, bound:bool}；armor_idx 指向护甲（-1 未穿）
var armor_idx: int = -1
## 时间制 buff（双倍经验卡等）：[{kind, until_unix, mult}]，同类不可叠加
var buffs: Array[Dictionary] = []
## 已学技能（attack = 攻击术）
var skills: Array[String] = []
## 战斗士气：连胜数 + 当前士气（胜利各 +1，战败/撤退清零，见 §4.2）
var streak: int = 0
var momentum: int = 0
## 安德鲁试炼 {state, kills, day}（day 轮换可每日重接）
var quest_andrew: Dictionary = {"state": "", "kills": 0, "day": -1}
## 西利亚海皇碎片 {shards, claimed}
var quest_siren: Dictionary = {"shards": 0, "claimed": false}
## 奥布帕斯每日谜语（当日序号，-1 未答过）
var riddle_day: int = -1
## 农田：长度=farm_plots，元素 {seed_id, planted_unix} 或 {}
var farm_plots: Array[Dictionary] = []
## 预约礼包一次性领取标记
var gift_claimed: bool = false


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
	exp_buff_left = 0
	exp_buff_mult = 10
	stamina = max_stamina()
	weight_bonus = 0
	armor_idx = -1
	buffs = []
	skills = []
	streak = 0
	momentum = 0
	quest_andrew = {"state": "", "kills": 0, "day": -1}
	quest_siren = {"shards": 0, "claimed": false}
	riddle_day = -1
	farm_plots = []
	_ensure_farm_plots()
	gift_claimed = false
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
		"exp_buff_left": exp_buff_left,
		"exp_buff_mult": exp_buff_mult,
		"stamina": stamina,
		"weight_bonus": weight_bonus,
		"armor_idx": armor_idx,
		"buffs": buffs.duplicate(true),
		"skills": skills.duplicate(),
		"streak": streak,
		"momentum": momentum,
		"quest_andrew": quest_andrew.duplicate(true),
		"quest_siren": quest_siren.duplicate(true),
		"riddle_day": riddle_day,
		"farm_plots": farm_plots.duplicate(true),
		"gift_claimed": gift_claimed,
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
		var gems: Array = []
		for g in inst.get("gems", []):
			var gid := String(g)
			if gid != "" and GameData.has_item(gid):
				gems.append(gid)
		# 旧档 equips 条目缺 gems/enhance/bound 时补默认值（契约 §4.1）
		equips.append({
			"id": id,
			"dur": clampi(int(inst.get("dur", dur_max)), 0, dur_max),
			"gems": gems,
			"enhance": clampi(int(inst.get("enhance", 0)), 0, Rules.smith_enhance_max()),
			"bound": bool(inst.get("bound", false)),
		})
	hand = clampi(int(p.get("hand", -1)), -1, equips.size() - 1)
	armor_idx = _valid_armor_idx(int(p.get("armor_idx", -1)))
	location = String(p.get("location", ""))
	if not GameData.has_scene(location):
		location = String(Rules.section("start").get("scene", "zaugun"))
	welfare_week = int(p.get("welfare_week", -1))
	dungeon_day = int(p.get("dungeon_day", -1))
	dungeon_kills = maxi(int(p.get("dungeon_kills", 0)), 0)
	dungeon_deadline = maxi(int(p.get("dungeon_deadline", 0)), 0)
	exp_buff_left = maxi(int(p.get("exp_buff_left", 0)), 0)
	exp_buff_mult = maxi(int(p.get("exp_buff_mult", 10)), 1)
	stamina = clampi(int(p.get("stamina", max_stamina())), 0, max_stamina())
	weight_bonus = maxi(int(p.get("weight_bonus", 0)), 0)
	buffs = []
	var saved_buffs: Array = p.get("buffs", [])
	for b: Dictionary in saved_buffs:
		buffs.append({
			"kind": String(b.get("kind", "")),
			"until_unix": maxi(int(b.get("until_unix", 0)), 0),
			"mult": maxf(float(b.get("mult", 1.0)), 1.0),
		})
	skills = []
	for s in p.get("skills", []):
		var sk := String(s)
		if sk != "" and not skills.has(sk):
			skills.append(sk)
	streak = maxi(int(p.get("streak", 0)), 0)
	momentum = clampi(int(p.get("momentum", 0)), 0, Rules.combat_momentum_max())
	var qa: Dictionary = p.get("quest_andrew", {})
	quest_andrew = {
		"state": String(qa.get("state", "")),
		"kills": maxi(int(qa.get("kills", 0)), 0),
		"day": int(qa.get("day", -1)),
	}
	var qs: Dictionary = p.get("quest_siren", {})
	quest_siren = {"shards": maxi(int(qs.get("shards", 0)), 0), "claimed": bool(qs.get("claimed", false))}
	riddle_day = int(p.get("riddle_day", -1))
	farm_plots = []
	var saved_plots: Array = p.get("farm_plots", [])
	for plot in saved_plots:
		if plot is Dictionary and not (plot as Dictionary).is_empty():
			var pd: Dictionary = plot
			farm_plots.append({"seed_id": String(pd.get("seed_id", "")), "planted_unix": maxi(int(pd.get("planted_unix", 0)), 0)})
		else:
			farm_plots.append({})
	_ensure_farm_plots()
	gift_claimed = bool(p.get("gift_claimed", false))
	hp_cur = clampi(int(p.get("hp", max_hp())), 0, max_hp())
	_emit_all()
	return true


# ---------- 派生属性 ----------

func exp_need() -> int:
	return Rules.exp_to_next(level)


func max_hp() -> int:
	return Rules.max_hp(level)


## 武器攻击区间（裸身 + 武器×强化倍率；宝石攻击由 gem_bonus 另加，见契约 §4.2）
func atk_range() -> Vector2i:
	var r := Rules.base_atk(level)
	var inst := hand_item()
	if not inst.is_empty():
		var wa: Array = GameData.get_item(String(inst.get("id", ""))).get("atk", [0, 0])
		var mult := _enhance_mult(inst)
		r = Vector2i(r.x + int(round(float(int(wa[0])) * mult)), r.y + int(round(float(int(wa[1])) * mult)))
	return r


func defense() -> int:
	return Rules.base_def(level)


## 装备负重：背包 + 全部装备（含宝石重量随装备条目不计，宝石重量走 bag 计量）
func weight() -> int:
	var w := 0
	for id: String in bag:
		w += int(GameData.get_item(id).get("weight", 0)) * int(bag[id])
	for inst in equips:
		w += int(GameData.get_item(String(inst.get("id", ""))).get("weight", 0))
	return w


func weight_used() -> int:
	return weight()


## 负重上限 = 成长曲线 + 乾坤袋加成（契约 §4.1 weight_max）
func weight_max() -> int:
	return Rules.weight_cap(level) + maxi(weight_bonus, 0)


func weight_cap() -> int:
	return weight_max()


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
	if per_weight > 0 and weight() + per_weight * count > weight_max():
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


## 加入一件装备实例，返回下标（-1 失败）。实例带完整扩展形状（契约 §4.1）
func add_equip(id: String) -> int:
	var def := GameData.get_item(id)
	if def.is_empty() or String(def.get("type", "")) != "equip":
		return -1
	if weight() + int(def.get("weight", 0)) > weight_max():
		return -1
	equips.append({"id": id, "dur": int(def.get("durability", 100)), "gems": [], "enhance": 0, "bound": false})
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


## 装备护甲（contract §4.1：须为 slot=armor、等级够、耐久 > 0）
func equip_armor(idx: int) -> bool:
	if idx < 0 or idx >= equips.size():
		return false
	var inst := equips[idx]
	var def := GameData.get_item(String(inst.get("id", "")))
	if String(def.get("slot", "weapon")) != "armor":
		return false
	if level < int(def.get("req_level", 1)):
		return false
	if int(inst.get("dur", 0)) <= 0:
		return false
	armor_idx = idx
	inventory_changed.emit()
	return true


func unequip_armor() -> void:
	armor_idx = -1
	inventory_changed.emit()


## 护甲防御（含强化倍率；耐久归零按 0 计，契约 §4.1）
func armor_def() -> int:
	var inst := _armor_item()
	if inst.is_empty() or int(inst.get("dur", 0)) <= 0:
		return 0
	var def := GameData.get_item(String(inst.get("id", "")))
	return int(round(float(maxi(int(def.get("def", 0)), 0)) * _enhance_mult(inst)))


## 实例耐久有效时返回该实例，否则 {}（下标悬空/耐久耗尽）
func _armor_item() -> Dictionary:
	if armor_idx < 0 or armor_idx >= equips.size():
		return {}
	return equips[armor_idx]


## 宝石合计加成 {atk, def, agi, hp}（契约 §4.1）
func gem_bonus() -> Dictionary:
	var bonus := {"atk": 0, "def": 0, "agi": 0, "hp": 0}
	for inst in equips:
		for g in inst.get("gems", []):
			var b: Dictionary = GameData.get_item(String(g)).get("bonus", {})
			for k: String in bonus:
				bonus[k] = int(bonus[k]) + int(b.get(k, 0))
	return bonus


func total_agility() -> int:
	var total := 1  # 基础敏捷 1（原版 Level1 agility=1✅，成长保守 +0）
	for inst in equips:
		total += int(GameData.get_item(String(inst.get("id", ""))).get("agility", 0))
	return total + int(gem_bonus().get("agi", 0))


func total_lucky() -> int:
	var total := 0
	for inst in equips:
		total += int(GameData.get_item(String(inst.get("id", ""))).get("lucky", 0))
	return total


func total_poison_res() -> int:
	var total := 0
	for inst in equips:
		total += int(GameData.get_item(String(inst.get("id", ""))).get("poison_res", 0))
	return total


## 强化倍率：1 + enhance × smith_enhance_pct_per%（契约 §4.1）
func _enhance_mult(inst: Dictionary) -> float:
	return 1.0 + float(maxi(int(inst.get("enhance", 0)), 0)) * float(Rules.smith_enhance_pct_per()) / 100.0


## 强化装备：龙泉水×1 + enhance_copper 铜贝，上限 enhance_max。
## 成功 enhance+1 并绑定（bound=true，卖/交易校验以实例 bound 为准）；返回 {ok, msg}
func enhance_equip(idx: int) -> Dictionary:
	if idx < 0 or idx >= equips.size():
		return {"ok": false, "msg": "没有这件装备。"}
	var inst := equips[idx]
	if int(inst.get("enhance", 0)) >= Rules.smith_enhance_max():
		return {"ok": false, "msg": "已强化到顶（%d/%d），不能再强化了。" % [int(inst.get("enhance", 0)), Rules.smith_enhance_max()]}
	if count_stack("longquanshui") <= 0:
		return {"ok": false, "msg": "强化需要一瓶龙泉水。"}
	if not spend_copper(Rules.smith_enhance_copper()):
		return {"ok": false, "msg": "强化要 %d 铜贝，你带的钱不够。" % Rules.smith_enhance_copper()}
	remove_stack("longquanshui", 1)
	inst["enhance"] = int(inst.get("enhance", 0)) + 1
	inst["bound"] = true
	inventory_changed.emit()
	return {"ok": true, "msg": "强化成功！%s 强化等级 %d，已绑定。" % [item_name(String(inst.get("id", ""))), int(inst["enhance"])]}


## 宝石镶嵌：校验装备插槽余量，宝石入 gems 并扣包；返回 {ok, msg}
func socket_gem(equip_idx: int, gem_id: String) -> Dictionary:
	if equip_idx < 0 or equip_idx >= equips.size():
		return {"ok": false, "msg": "没有这件装备。"}
	var gem_def := GameData.get_item(gem_id)
	if gem_def.is_empty() or String(gem_def.get("type", "")) != "gem":
		return {"ok": false, "msg": "这不是能镶嵌的宝石。"}
	if count_stack(gem_id) <= 0:
		return {"ok": false, "msg": "你包里没有这种宝石。"}
	var inst := equips[equip_idx]
	var slots := int(GameData.get_item(String(inst.get("id", ""))).get("slots", 0))
	var gems: Array = inst.get("gems", [])
	if gems.size() >= slots:
		return {"ok": false, "msg": "这件装备的插槽已经满了（%d/%d）。" % [gems.size(), slots]}
	remove_stack(gem_id, 1)
	gems.append(gem_id)
	inst["gems"] = gems
	inventory_changed.emit()
	return {"ok": true, "msg": "镶嵌成功！%s 已嵌入 %s。" % [item_name(gem_id), item_name(String(inst.get("id", "")))]}


## 手持武器消耗 1 点耐久，损坏时返回其名字（并移除）
func damage_hand() -> String:
	if hand < 0 or hand >= equips.size():
		return ""
	var inst := equips[hand]
	inst["dur"] = maxi(int(inst.get("dur", 0)) - 1, 0)
	if int(inst["dur"]) <= 0:
		var broke := item_name(String(inst.get("id", "")))
		_remove_equip_at(hand)
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
## 手持件先自动卸下；其后手持/护甲下标前移，避免悬空索引。
func sell_equip(idx: int) -> Dictionary:
	if idx < 0 or idx >= equips.size():
		return {}
	var inst := equips[idx]
	_remove_equip_at(idx)
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


## 使用药品，返回 ""=成功 / "none"=没有该药 / "full"=满血（扩展契约 §4.1）。
## 带 exp_buff 的丹药走加速 buff：不回体力、不受满血限制。
func use_drug(id: String) -> String:
	var def := GameData.get_item(id)
	if def.is_empty() or String(def.get("type", "")) != "drug" or count_stack(id) <= 0:
		return "none"
	if def.has("exp_buff"):
		var buff: Dictionary = def.get("exp_buff", {})
		apply_exp_buff(int(buff.get("battles", 10)), int(buff.get("multiplier", 10)))
		remove_stack(id, 1)
		return ""
	if hp_cur >= max_hp():
		return "full"
	heal(int(def.get("heal", 0)))
	remove_stack(id, 1)
	return ""


## 移除下标处装备实例并前移其后引用（hand/armor_idx 由调用方按需校正）
func _remove_equip_at(idx: int) -> void:
	equips.remove_at(idx)
	if armor_idx == idx:
		armor_idx = -1
	elif armor_idx > idx:
		armor_idx -= 1


## 悬空/非护甲下标清洗为 -1（读档兜底）
func _valid_armor_idx(idx: int) -> int:
	if idx < 0 or idx >= equips.size():
		return -1
	var def := GameData.get_item(String(equips[idx].get("id", "")))
	return idx if String(def.get("slot", "weapon")) == "armor" else -1


# ---------- 生活体力（契约 §4.1） ----------

## 体力上限 = life.stamina_max + (level-1) × stamina_per_level
func max_stamina() -> int:
	return Rules.life_stamina_max() + maxi(level - 1, 0) * Rules.life_stamina_per_level()


## 消耗生活体力：不足返回 false；成功后检查 <auto_stamina_pct% 自动吃奶瓶/体力宝
func spend_stamina(n: int) -> bool:
	if n <= 0 or stamina < n:
		return false
	stamina -= n
	_auto_stamina_drink()
	return true


func gain_stamina(n: int) -> void:
	if n <= 0:
		return
	stamina = mini(stamina + n, max_stamina())


## 体力低于 auto_stamina_pct% 时自动食用包内 stamina 类道具（小份优先，🔍原版文案）
func _auto_stamina_drink() -> void:
	var threshold := max_stamina() * Rules.life_auto_stamina_pct() / 100
	if stamina >= threshold:
		return
	var cands: Array[Dictionary] = []
	for id: String in bag:
		var eff: Dictionary = GameData.get_item(id).get("effect", {})
		var value := maxi(int(eff.get("value", 0)), 0)
		if String(eff.get("kind", "")) == "stamina" and value > 0 and count_stack(id) > 0:
			cands.append({"id": id, "value": value})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["value"]) < int(b["value"]))
	for c in cands:
		var cid := String(c["id"])
		while stamina < threshold and count_stack(cid) > 0:
			remove_stack(cid, 1)
			gain_stamina(int(c["value"]))


# ---------- 时间制 buff（契约 §4.1） ----------

## 追加时间制 buff（小时制持续）；同类不可叠加（双倍经验卡✅）：刷新持续与倍率
func add_time_buff(kind: String, hours: float, mult: float) -> void:
	for i in range(buffs.size() - 1, -1, -1):
		if String(buffs[i].get("kind", "")) == kind:
			buffs.remove_at(i)
	buffs.append({
		"kind": kind,
		"until_unix": int(Time.get_unix_time_from_system()) + int(round(hours * 3600.0)),
		"mult": maxf(mult, 1.0),
	})


func clear_buffs() -> void:
	buffs = []


## 经验倍率 = max(场次制加速丹（未耗尽）, 时间制 exp_buff（未过期）)，无则 1.0（契约 §4.1）
func exp_mult() -> float:
	var mult := 1.0
	if exp_buff_left > 0:
		mult = maxf(mult, float(maxi(exp_buff_mult, 1)))
	var now := Time.get_unix_time_from_system()
	for b: Dictionary in buffs:
		if String(b.get("kind", "")) == "exp_buff" and float(b.get("until_unix", 0.0)) > now:
			mult = maxf(mult, maxf(float(b.get("mult", 1.0)), 1.0))
	return mult


# ---------- 经验加速丹 buff ----------

## 激活加速：剩余场次取较大值，倍率随最新一颗
func apply_exp_buff(battles: int, multiplier: int) -> void:
	exp_buff_left = maxi(exp_buff_left, maxi(battles, 0))
	exp_buff_mult = maxi(multiplier, 1)


## 战斗胜利结算时消耗 1 场次，返回生效倍率（未激活返回 1）
func consume_exp_buff() -> int:
	if exp_buff_left <= 0:
		return 1
	exp_buff_left -= 1
	return exp_buff_mult


# ---------- 战斗士气（契约 §4.2） ----------

## 胜利：连胜 +1，士气 +1（封顶 momentum_max）
func bump_streak() -> void:
	streak += 1
	momentum = mini(momentum + 1, Rules.combat_momentum_max())


## 战败/撤退：连胜与士气清零
func reset_streak() -> void:
	streak = 0
	momentum = 0


# ---------- 技能（契约 §4.1） ----------

## 学习技能，已学返回 false
func learn_skill(s: String) -> bool:
	if s == "" or has_skill(s):
		return false
	skills.append(s)
	return true


func has_skill(s: String) -> bool:
	return skills.has(s)


# ---------- 农田（契约 §4.1 + §5.3） ----------

## 播种：扣 1 颗种子并占格；返回 {ok, msg}
func plant_plot(i: int, seed_id: String, now: int) -> Dictionary:
	_ensure_farm_plots()
	if i < 0 or i >= farm_plots.size():
		return {"ok": false, "msg": "没有这块地。"}
	if not (farm_plots[i] as Dictionary).is_empty():
		return {"ok": false, "msg": "这块地已经种上了。"}
	if count_stack(seed_id) <= 0:
		return {"ok": false, "msg": "你包里没有这种种子。"}
	if not remove_stack(seed_id, 1):
		return {"ok": false, "msg": "种子不见了。"}
	farm_plots[i] = {"seed_id": seed_id, "planted_unix": maxi(now, 0)}
	return {"ok": true, "msg": "你把%s种进了地里。" % item_name(seed_id)}


## 收获：成熟判定 + 收获入包 + 50% 概率返还种子；返回 {ok, msg, gain:{id:count}}
func harvest_plot(i: int, now: int) -> Dictionary:
	_ensure_farm_plots()
	if i < 0 or i >= farm_plots.size():
		return {"ok": false, "msg": "没有这块地。", "gain": {}}
	var plot: Dictionary = farm_plots[i]
	if plot.is_empty():
		return {"ok": false, "msg": "这块地空着呢。", "gain": {}}
	var seed_id := String(plot.get("seed_id", ""))
	if now - maxi(int(plot.get("planted_unix", 0)), 0) < Rules.life_farm_grow_sec():
		return {"ok": false, "msg": "庄稼还没成熟，再等等。", "gain": {}}
	# 种子 → 作物：去 _zhongzi 后缀（mucao_zhongzi → mucao；找不到时按种子本身）
	var crop := seed_id.trim_suffix("_zhongzi")
	if not GameData.has_item(crop):
		crop = seed_id
	var count := Rules.life_farm_harvest_count()
	var give_seed := rng.randi() % 100 < 50  # 50% 概率返还种子（§5.3）
	var need_weight := int(GameData.get_item(crop).get("weight", 0)) * count
	if give_seed and count_stack(seed_id) <= 0:
		need_weight += int(GameData.get_item(seed_id).get("weight", 0))
	if weight() + need_weight > weight_max():
		return {"ok": false, "msg": "背包塞不下收成，庄稼先留在地里。", "gain": {}}
	var gain := {crop: count}
	if not add_stack(crop, count):
		return {"ok": false, "msg": "背包塞不下收成，庄稼先留在地里。", "gain": {}}
	if give_seed:
		add_stack(seed_id, 1)
		gain[seed_id] = 1
	farm_plots[i] = {}
	return {"ok": true, "msg": "你收获了%s×%d！" % [item_name(crop), count], "gain": gain}


## 地块数对齐 config.life.farm_plots（读档/使用前兜底）
func _ensure_farm_plots() -> void:
	var want := maxi(Rules.life_farm_plots(), 0)
	while farm_plots.size() > want:
		farm_plots.remove_at(farm_plots.size() - 1)
	while farm_plots.size() < want:
		farm_plots.append({})


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


# ---------- 改名（契约 §4.1；等级校验放 router） ----------

func rename(nick: String) -> bool:
	var clean := nick.strip_edges()
	if clean.is_empty() or clean.length() > 12:
		return false
	nickname = clean
	return true


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
