class_name EventRouter
extends RefCounted
## 事件分发器（对应原版「_简单超文本框1_自定义超链接被单击」主事件分发）。
## handle(event) → 校验/改状态（经 PlayerCore）→ 生成新 BBCode 页面。
## UI 层只读 page / input_mode / needs_save / toast，不直接改游戏状态。

signal game_started
signal continue_requested

var player: PlayerCore
var bus: Variant = null

var page: String = ""
var input_mode: String = ""
var needs_save := false

var combat: CombatEngine = null
var _combat_show_self := false


func setup(p_player: PlayerCore, p_bus: Variant = null) -> void:
	player = p_player
	bus = p_bus


## 进入游戏后渲染当前场景（GameScreen 首帧调用）
func open_start_scene() -> void:
	_goto(player.location)


func handle(event: String, param: String = "") -> void:
	input_mode = ""
	var parts := event.split(":")
	var cmd := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	var arg2 := parts[2] if parts.size() > 2 else ""
	match cmd:
		"story":
			_story(arg)
		"continue":
			continue_requested.emit()
		"create":
			_create(arg, param)
		"goto":
			_goto(arg)
		"map":
			page = Pages.city_map()
		"status":
			page = Pages.status_page(player)
		"items":
			page = Pages.items_page(player, arg)
		"npc":
			_npc(arg, arg2)
		"equip_view":
			page = Pages.equip_detail(player, int(arg))
		"equip_use":
			_equip_use(int(arg))
		"equip_off":
			_equip_off(int(arg))
		"welfare_claim":
			_welfare_claim()
		"heal":
			_heal()
		"confess":
			player.add_sin(-Rules.confess_reduce())
			page = Pages.confess_result(player)
			needs_save = true
		"bank":
			page = Pages.bank_main(player)
		"bank_deposit":
			page = Pages.bank_deposit_page(player)
		"deposit":
			_deposit(arg)
		"bank_withdraw":
			page = Pages.bank_withdraw_page(player)
		"withdraw":
			_withdraw(arg)
		"casino", "again":
			page = Pages.casino_main()
		"dice_page":
			page = Pages.dice_page()
		"dice":
			_dice(arg)
		"rps_page":
			page = Pages.rps_page()
		"rps":
			_rps(arg)
		"market":
			page = Pages.market_main(player)
		"buy":
			_buy(arg, arg2)
		"sell_page":
			page = Pages.sell_page(player)
		"sell":
			_sell(arg, arg2)
		"teleport":
			page = Pages.teleport_page(player)
		"tp":
			_tp(arg)
		"sail":
			page = Pages.sail_page()
		"dungeon_try":
			page = Pages.notice_page("威尼斯地宫：暂未开发区域，请耐心等待", "back_game", "返回")
		"fight":
			_fight(arg)
		"attack":
			_attack()
		"view":
			_combat_show_self = not _combat_show_self
			_render_combat("")
		"retreat":
			_retreat()
		"combat_reward":
			page = Pages.reward_page(combat, player)
		"back_game", "combat_leave":
			_back_game()
		_:
			page = Pages.notice_page("这个入口暂时通向虚空……", "back_game", "返回游戏")


# ---------- 开场 / 建号 ----------

func _story(arg: String) -> void:
	var idx := int(arg)
	if idx == 99:
		page = Pages.create_page("")
		input_mode = "char_name"
	elif idx < 0:
		page = Pages.intro_title(_has_save())
	else:
		page = Pages.intro_page(idx)


func _create(gender: String, name_text: String) -> void:
	var clean := name_text.strip_edges()
	if clean.is_empty():
		page = Pages.create_page("名字不能为空，请重新输入。")
		input_mode = "char_name"
		return
	if clean.length() > 12:
		page = Pages.create_page("名字太长了（最多 12 个字）。")
		input_mode = "char_name"
		return
	player.new_game(clean, gender)
	page = ""
	needs_save = true
	game_started.emit()


func _has_save() -> bool:
	return FileAccess.file_exists("user://save.bin") or FileAccess.file_exists("user://save.bak")


# ---------- 移动 ----------

func _goto(scene_id: String) -> void:
	if not GameData.has_scene(scene_id):
		page = Pages.notice_page("那条路走不通……", "back_game", "返回游戏")
		return
	combat = null
	player.set_location(scene_id)
	page = Pages.scene_page(player, scene_id)
	needs_save = true
	if bus != null:
		bus.scene_entered.emit(StringName(scene_id))


func _back_game() -> void:
	if combat != null and not combat.finished:
		_render_combat("战斗正酣，无法离开！想跑请点撤退。")
		return
	combat = null
	_goto(player.location)


# ---------- NPC ----------

func _npc(scene_id: String, npc_id: String) -> void:
	var scene := GameData.get_scene(scene_id)
	for npc: Dictionary in scene.get("npcs", []):
		if String(npc.get("id", "")) != npc_id:
			continue
		match String(npc.get("kind", "flavor")):
			"flavor":
				page = Pages.npc_flavor_page(npc, player)
			"welfare":
				page = Pages.welfare_page(player)
			"church":
				page = Pages.church_page(player)
			"bank":
				page = Pages.bank_main(player)
			"casino":
				page = Pages.casino_main()
			"market":
				page = Pages.market_main(player)
			"teleport":
				page = Pages.teleport_page(player)
			"sail":
				page = Pages.sail_page()
			"dungeon":
				page = Pages.explorer_page(player)
			_:
				page = Pages.npc_flavor_page(npc, player)
		return
	page = Pages.notice_page("这里什么人也没有。", "back_game", "返回游戏")


# ---------- 战斗 ----------

func _fight(monster_id: String) -> void:
	if not GameData.has_monster(monster_id):
		page = Pages.notice_page("目标不见了。", "back_game", "返回游戏")
		return
	combat = CombatEngine.new(monster_id, player)
	_combat_show_self = false
	_render_combat("")


func _attack() -> void:
	if combat == null:
		_back_game()
		return
	combat.attack_round(player)
	needs_save = true
	if bus != null and combat.weapon_broke_name != "":
		bus.weapon_broken.emit(combat.weapon_broke_name)
	if combat.finished:
		if combat.won:
			if bus != null:
				bus.enemy_defeated.emit(StringName(combat.monster_id))
				bus.battle_won.emit(StringName(combat.monster_id))
				if combat.reward_item != "":
					bus.item_obtained.emit(StringName(combat.reward_item), 1)
				if combat.level_gained > 0:
					bus.leveled_up.emit(player.level)
			page = Pages.win_page(combat)
		else:
			var lost := Rules.death_loss(player.copper)
			player.take_copper(lost)
			player.heal(Rules.revive_hp(player.max_hp()))
			player.set_location(Rules.revive_scene())
			page = Pages.lose_page(combat, lost, String(GameData.get_scene(player.location).get("name", "")))
			if bus != null:
				bus.battle_lost.emit(StringName(combat.monster_id))
				bus.player_died.emit(StringName(combat.monster_id))
	else:
		_render_combat("")


func _retreat() -> void:
	if combat == null or combat.finished:
		_back_game()
		return
	var cost := combat.retreat_cost()
	if not player.spend_copper(cost):
		_render_combat("撤退要 %d 铜贝，你带的钱不够！" % cost)
		return
	combat = null
	page = Pages.retreat_page(cost)
	needs_save = true


func _render_combat(notice: String) -> void:
	page = Pages.combat_page(combat, player, _combat_show_self, notice)


# ---------- 教堂 / 福利 ----------

func _heal() -> void:
	player.heal(Rules.heal_amount())
	page = Pages.heal_result(player)
	needs_save = true


func _welfare_claim() -> void:
	if not player.welfare_claimable():
		page = Pages.welfare_page(player)
		return
	player.mark_welfare_claimed()
	var amount := Rules.welfare_copper()
	player.add_copper(amount)
	page = Pages.welfare_result(amount)
	needs_save = true
	if bus != null:
		bus.welfare_claimed.emit(amount)


# ---------- 银行 ----------

func _deposit(arg: String) -> void:
	var per := Rules.copper_per_silver()
	var silver := player.copper / per if arg == "all" else int(arg)
	if silver <= 0 or not player.bank_deposit(silver):
		page = Pages.notice_page("银行职员：这点钱可存不进来。", "bank_deposit", "返回")
		return
	page = Pages.bank_result(true, silver)
	needs_save = true


func _withdraw(arg: String) -> void:
	var silver := player.bank_silver if arg == "all" else int(arg)
	if silver <= 0 or not player.bank_withdraw(silver):
		page = Pages.notice_page("银行职员：银行破产.....（并没有，只是你没有那么多存款）", "bank_withdraw", "返回")
		return
	page = Pages.bank_result(false, silver)
	needs_save = true


# ---------- 赌场 ----------

func _dice(side: String) -> void:
	if not player.spend_copper(Rules.casino_bet()):
		page = Pages.notice_page(Pages.casino_insufficient_line(player.gender), "dice_page", "返回")
		return
	var dice := [
		player.rng.randi_range(1, 6),
		player.rng.randi_range(1, 6),
		player.rng.randi_range(1, 6),
	]
	var total := int(dice[0]) + int(dice[1]) + int(dice[2])
	var is_triple: bool = dice[0] == dice[1] and dice[1] == dice[2]
	var big := total >= 11
	var won: bool = (not is_triple) and ((side == "big") == big)
	if won:
		player.add_copper(Rules.casino_win())
	var summary := "%d 点（%s%s）" % [total, "大" if big else "小", "，豹子通杀" if is_triple else ""]
	page = Pages.dice_result(player, dice, won, summary)
	needs_save = true


const RPS_NAMES := {"rock": "石头", "scissors": "剪刀", "paper": "布"}
const RPS_BEATS := {"rock": "scissors", "scissors": "paper", "paper": "rock"}


func _rps(move: String) -> void:
	if not RPS_NAMES.has(move):
		page = Pages.casino_main()
		return
	if not player.spend_copper(Rules.casino_bet()):
		page = Pages.notice_page(Pages.casino_insufficient_line(player.gender), "rps_page", "返回")
		return
	var keys := RPS_NAMES.keys()
	var mm: String = keys[player.rng.randi() % keys.size()]
	var outcome := "draw"
	if move != mm:
		outcome = "win" if String(RPS_BEATS[move]) == mm else "lose"
	match outcome:
		"win":
			player.add_copper(Rules.casino_win())
		"draw":
			player.add_copper(Rules.casino_bet())
	page = Pages.rps_result(player, String(RPS_NAMES[move]), String(RPS_NAMES[mm]), outcome)
	needs_save = true


# ---------- 市场 ----------

func _buy(item_id: String, qty_text: String) -> void:
	var def := GameData.get_item(item_id)
	var qty := int(qty_text)
	if def.is_empty() or qty <= 0:
		page = Pages.market_main(player)
		return
	var cost := int(def.get("buy_price", 0)) * qty
	var per_weight := int(def.get("weight", 0))
	if per_weight > 0 and player.weight() + per_weight * qty > player.weight_cap():
		page = Pages.market_result(player, "供应商：这么多货你背不动，少买点吧。")
		return
	if not player.spend_copper(cost):
		page = Pages.market_result(player, "供应商：钱不够啊，%s" % Pages.casino_insufficient_line(player.gender).replace("博彩MM：", ""))
		return
	if not player.add_stack(item_id, qty):
		player.add_copper(cost)
		page = Pages.market_result(player, "供应商：你身上放不下了，先卖掉一些再来。")
		return
	page = Pages.market_result(player, "你买下了 %d 箱%s，花费 %d 铜贝。" % [qty, player.item_name(item_id), cost])
	needs_save = true
	if bus != null:
		bus.item_obtained.emit(StringName(item_id), qty)


func _sell(item_id: String, qty_text: String) -> void:
	var def := GameData.get_item(item_id)
	var qty := count_sell_qty(item_id, qty_text)
	if def.is_empty() or qty <= 0:
		page = Pages.sell_page(player)
		return
	if not player.remove_stack(item_id, qty):
		page = Pages.market_result(player, "供应商：你哪来那么多货？")
		return
	var earn := Rules.sell_price(int(def.get("buy_price", 0))) * qty
	player.add_copper(earn)
	page = Pages.market_result(player, "你卖掉了 %d 箱%s，进账 %d 铜贝。" % [qty, player.item_name(item_id), earn])
	needs_save = true


func count_sell_qty(item_id: String, qty_text: String) -> int:
	return player.count_stack(item_id) if qty_text == "all" else int(qty_text)


# ---------- 码头 / 传送 ----------

func _tp(arg: String) -> void:
	var idx := int(arg)
	if idx < 0 or idx >= GameData.ports.size():
		page = Pages.teleport_page(player)
		return
	# 原版除威尼斯外所有港口均未实现：占位文案逐字保留
	page = Pages.notice_page("%s：暂未开发区域，请耐心等待" % GameData.ports[idx], "teleport", "返回码头")


# ---------- 装备 ----------

func _equip_use(idx: int) -> void:
	var err := player.equip_hand(idx)
	match err:
		"":
			page = Pages.equip_detail(player, idx)
			needs_save = true
		"level":
			page = Pages.notice_page("你的等级还不够，用不了这件装备。", "equip_view:%d" % idx, "返回")
		"broken":
			page = Pages.notice_page("这件装备已经损坏了。", "equip_view:%d" % idx, "返回")
		_:
			page = Pages.items_page(player, "equip")


func _equip_off(idx: int) -> void:
	player.unequip_hand()
	page = Pages.equip_detail(player, idx)
	needs_save = true
