class_name CombatEngine
extends RefCounted
## 单场战斗：双方攻击区间随机 + 防御减伤（《游戏设计机制.md》§6.3 推断模型）。
## 每次点击攻击结算一回合，玩家先手；武器每击消耗 1 点耐久。
## 扩展（契约 plan-v2 §4.2）：士气增伤、幸运一击、敏捷闪避、护甲/宝石防御、
## 怪物毒伤（毒抗减免）、攻击术技能；胜利 bump_streak，战败 reset_streak。

const LOG_KEEP := 4

var monster_id: String = ""
var monster_name: String = ""
var monster_level: int = 1
var monster_atk_min: int = 1
var monster_atk_max: int = 1
var monster_def: int = 0
var monster_poison: int = 0
var monster_hp: int = 1
var monster_hp_max: int = 1
var finished := false
var won := false
var player_died := false
var reward_exp := 0
var reward_copper := 0
var reward_item := ""
var reward_equip := ""
var level_gained := 0
var exp_mult := 1
var weapon_broke_name := ""
## 攻击术本场已用标记（契约 §4.2 cast_skill）
var skill_used_this_fight := false
var log_lines: PackedStringArray = []


func _init(mid: String, player: PlayerCore) -> void:
	var m := GameData.get_monster(mid)
	if m.is_empty():
		push_error("CombatEngine: 未知怪物 %s" % mid)
		return
	monster_id = mid
	monster_name = String(m.get("name", "???"))
	monster_level = maxi(int(m.get("level", 1)), 1)
	monster_hp = maxi(int(m.get("hp", 1)), 1)
	monster_hp_max = monster_hp
	monster_def = maxi(int(m.get("def", 0)), 0)
	monster_poison = maxi(int(m.get("poison", 0)), 0)
	var atk: Array = m.get("atk", [1, 1])
	monster_atk_min = int(atk[0])
	monster_atk_max = maxi(int(atk[1]), monster_atk_min)


## 结算一回合（玩家先手，怪还手；任一方体力 ≤ 0 即结束）
func attack_round(player: PlayerCore) -> void:
	if finished:
		return
	_player_strike(player, 100, "")
	weapon_broke_name = player.damage_hand()
	if weapon_broke_name != "":
		log_lines.append("「%s」不堪重负，断成了两截！" % weapon_broke_name)
	if monster_hp <= 0:
		_finish_win(player)
		return
	_monster_strike(player, false)


## 攻击术（契约 §4.2）：已学 attack + 本场未用 + 扣 skill_stamina 体力，
## 额外以 skill_mult_pct% 倍率攻击一次；返回 {ok, msg}
func cast_skill(player: PlayerCore) -> Dictionary:
	if finished:
		return {"ok": false, "msg": "战斗已经结束了。"}
	if not player.has_skill("attack"):
		return {"ok": false, "msg": "你还没学会攻击术。"}
	if skill_used_this_fight:
		return {"ok": false, "msg": "本场已经用过攻击术了。"}
	if not player.spend_stamina(Rules.combat_skill_stamina()):
		return {"ok": false, "msg": "施展攻击术要 %d 点体力，你体力不足。" % Rules.combat_skill_stamina()}
	skill_used_this_fight = true
	_player_strike(player, Rules.combat_skill_mult_pct(), "你运转攻击术，")
	weapon_broke_name = player.damage_hand()
	if weapon_broke_name != "":
		log_lines.append("「%s」不堪重负，断成了两截！" % weapon_broke_name)
	if monster_hp <= 0:
		_finish_win(player)
		return {"ok": true, "msg": ""}
	_monster_strike(player, false)
	return {"ok": true, "msg": ""}


## 怪物还击一回合（玩家战斗中用药后）：玩家不出手、不耗武器耐久（扩展契约 §4.2）
func monster_counter(player: PlayerCore) -> void:
	if finished:
		return
	_monster_strike(player, true)


func retreat_cost() -> int:
	return Rules.retreat_cost(monster_level)


## 玩家出手：dmg_mult_pct 为技能倍率（100=普通），prefix 为日志前缀。
## 伤害 = atk_range × 士气加成 − 怪 def（宝石 atk 已并入 atk_range，口径并入 ui-opt 契约 §2.1）；
## 幸运一击按 total_lucky 概率触发 ×lucky_mult_pct%。
func _player_strike(player: PlayerCore, dmg_mult_pct: int, prefix: String) -> void:
	var range_atk := player.atk_range()
	var raw := player.rng.randi_range(range_atk.x, range_atk.y)
	raw = raw * (100 + maxi(player.momentum, 0) * Rules.combat_momentum_atk_pct_per()) / 100
	var dmg := maxi(raw - monster_def, 0)
	var lucky := player.total_lucky() > 0 and player.rng.randi() % 100 < player.total_lucky() * Rules.combat_lucky_pct_per()
	if lucky:
		dmg = dmg * Rules.combat_lucky_mult_pct() / 100
	dmg = dmg * maxi(dmg_mult_pct, 0) / 100
	monster_hp = maxi(monster_hp - dmg, 0)
	if prefix != "":
		log_lines.append("%s打出 %d 点伤害，命中%s！" % [prefix, dmg, monster_name])
	elif lucky:
		log_lines.append("幸运一击！你挥出 %d 点攻击，对%s造成 %d 点伤害。" % [raw, monster_name, dmg])
	else:
		log_lines.append("你挥出 %d 点攻击，对%s造成 %d 点伤害。" % [raw, monster_name, dmg])


## 怪物出手：敏捷闪避（命中率 = 100% − agi×per%，封顶 dodge_pct_max）→
## 防御减伤（defense() 已含基础 + 护甲 + 宝石 def，口径并入 ui-opt 契约 §2.1）→
## 命中后附加毒伤（毒抗减免，契约 §4.2）。
func _monster_strike(player: PlayerCore, while_drinking: bool) -> void:
	var hit_pct := 100 - mini(player.total_agility() * Rules.combat_dodge_pct_per_agi(), Rules.combat_dodge_pct_max())
	if player.rng.randi() % 100 >= hit_pct:
		if while_drinking:
			log_lines.append("%s趁你用药出手，你灵巧地闪开了。" % monster_name)
		else:
			log_lines.append("你灵巧地闪开了%s的攻击。" % monster_name)
		_trim_log()
		return
	var m_hit := player.rng.randi_range(monster_atk_min, monster_atk_max)
	var pdef := player.defense()
	var m_dmg := maxi(m_hit - pdef, 0)
	var dead := player.hurt(m_dmg)
	if while_drinking:
		log_lines.append("%s趁你用药还击，造成 %d 点伤害，你剩余体力 %d/%d。" % [monster_name, m_dmg, player.hp_cur, player.max_hp()])
	else:
		log_lines.append("%s还击造成 %d 点伤害，你剩余体力 %d/%d。" % [monster_name, m_dmg, player.hp_cur, player.max_hp()])
	var poison := maxi(monster_poison - player.total_poison_res(), 0)
	if poison > 0:
		dead = player.hurt(poison) or dead
		log_lines.append("毒素侵入伤口！你额外受到 %d 点毒素伤害，剩余体力 %d/%d。" % [poison, player.hp_cur, player.max_hp()])
	if dead:
		finished = true
		player_died = true
		player.reset_streak()
	_trim_log()


## 战斗收尾：发奖励 + 士气结算（契约 §4.2 胜利 bump_streak）
func _finish_win(player: PlayerCore) -> void:
	finished = true
	won = true
	_grant_win_rewards(player)
	player.bump_streak()
	_trim_log()


func _grant_win_rewards(player: PlayerCore) -> void:
	var m := GameData.get_monster(monster_id)
	var exp_range: Array = m.get("exp", [1, 1])
	var raw_exp := player.rng.randi_range(int(exp_range[0]), int(exp_range[1]))
	# 经验加成：场次制加速丹（结算消耗 1 场次）与时间制 buff 取大（契约 §4.2）
	var session_mult := player.consume_exp_buff()
	exp_mult = maxi(session_mult, int(round(player.exp_mult())))
	reward_exp = raw_exp * exp_mult
	var copper_range: Array = m.get("copper", [0, 0])
	reward_copper = player.rng.randi_range(int(copper_range[0]), int(copper_range[1]))
	if player.rng.randi() % 100 < int(m.get("drop_rate", 0)):
		reward_item = String(m.get("drop_item", ""))
	# 装备掉落（独立于材料掉落，扩展契约 §4.6）：命中入包，放不下降级为堆叠
	var drop_equip: Dictionary = m.get("drop_equip", {})
	if not drop_equip.is_empty() and player.rng.randi() % 100 < int(drop_equip.get("rate", 0)):
		var eq_id := String(drop_equip.get("id", ""))
		if eq_id != "" and GameData.has_item(eq_id):
			reward_equip = eq_id
			if player.add_equip(eq_id) < 0:
				player.add_stack(eq_id, 1)
	level_gained = player.add_exp(reward_exp)
	player.add_copper(reward_copper)
	if reward_item != "":
		if player.add_equip(reward_item) < 0:
			player.add_stack(reward_item, 1)


func _trim_log() -> void:
	if log_lines.size() > LOG_KEEP:
		log_lines = log_lines.slice(log_lines.size() - LOG_KEEP)
