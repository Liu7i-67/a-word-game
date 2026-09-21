class_name CombatEngine
extends RefCounted
## 单场战斗：双方攻击区间随机 + 防御减伤（《游戏设计机制.md》§6.3 推断模型）。
## 每次点击攻击结算一回合，玩家先手；武器每击消耗 1 点耐久。

const LOG_KEEP := 4

var monster_id: String = ""
var monster_name: String = ""
var monster_level: int = 1
var monster_atk_min: int = 1
var monster_atk_max: int = 1
var monster_def: int = 0
var monster_hp: int = 1
var monster_hp_max: int = 1
var finished := false
var won := false
var player_died := false
var reward_exp := 0
var reward_copper := 0
var reward_item := ""
var level_gained := 0
var weapon_broke_name := ""
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
	var atk: Array = m.get("atk", [1, 1])
	monster_atk_min = int(atk[0])
	monster_atk_max = maxi(int(atk[1]), monster_atk_min)


## 结算一回合（玩家先手，怪还手；任一方体力 ≤ 0 即结束）
func attack_round(player: PlayerCore) -> void:
	if finished:
		return
	var range_atk := player.atk_range()
	var my_hit := player.rng.randi_range(range_atk.x, range_atk.y)
	var my_dmg := maxi(my_hit - monster_def, 0)
	monster_hp = maxi(monster_hp - my_dmg, 0)
	log_lines.append("你挥出 %d 点攻击，对%s造成 %d 点伤害。" % [my_hit, monster_name, my_dmg])
	weapon_broke_name = player.damage_hand()
	if weapon_broke_name != "":
		log_lines.append("「%s」不堪重负，断成了两截！" % weapon_broke_name)
	if monster_hp <= 0:
		finished = true
		won = true
		_grant_win_rewards(player)
		_trim_log()
		return
	var m_hit := player.rng.randi_range(monster_atk_min, monster_atk_max)
	var m_dmg := maxi(m_hit - player.defense(), 0)
	var dead := player.hurt(m_dmg)
	log_lines.append("%s还击造成 %d 点伤害，你剩余体力 %d/%d。" % [monster_name, m_dmg, player.hp_cur, player.max_hp()])
	if dead:
		finished = true
		player_died = true
	_trim_log()


func retreat_cost() -> int:
	return Rules.retreat_cost(monster_level)


func _grant_win_rewards(player: PlayerCore) -> void:
	var m := GameData.get_monster(monster_id)
	var exp_range: Array = m.get("exp", [1, 1])
	reward_exp = player.rng.randi_range(int(exp_range[0]), int(exp_range[1]))
	var copper_range: Array = m.get("copper", [0, 0])
	reward_copper = player.rng.randi_range(int(copper_range[0]), int(copper_range[1]))
	if player.rng.randi() % 100 < int(m.get("drop_rate", 0)):
		reward_item = String(m.get("drop_item", ""))
	level_gained = player.add_exp(reward_exp)
	player.add_copper(reward_copper)
	if reward_item != "":
		if player.add_equip(reward_item) < 0:
			player.add_stack(reward_item, 1)


func _trim_log() -> void:
	if log_lines.size() > LOG_KEEP:
		log_lines = log_lines.slice(log_lines.size() - LOG_KEEP)
