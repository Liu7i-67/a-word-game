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
		"trade_buy":
			_trade_buy(arg, arg2)
		"trade_sell":
			_trade_sell(arg, arg2)
		"rumor":
			_rumor()
		"sell_equip_page":
			page = Pages.sell_equip_page(player)
		"sell_equip":
			_sell_equip(int(arg))
		"teleport":
			page = Pages.teleport_page(player)
		"tp":
			_tp(arg)
		"sail":
			page = Pages.sail_page()
		"dungeon_try":
			_dungeon_try()
		"use_drug":
			_use_drug(arg)
		"combat_drug":
			_combat_drug_page()
		"combat_use":
			_combat_use(arg)
		"combat_back":
			if combat == null or combat.finished:
				_back_game()
			else:
				_render_combat("")
		"buy_drug":
			_buy_drug(arg, arg2)
		"shop":
			page = Pages.shop_page(player)
		"smith":
			page = Pages.smith_page(player)
		"repair_hand":
			_repair_hand()
		"forge_page":
			page = Pages.forge_page(player)
		"forge":
			_forge(arg)
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
	if scene_id == Rules.dungeon_scene():
		_enter_dungeon()
		return
	player.set_location(scene_id)
	page = Pages.scene_page(player, scene_id)
	needs_save = true
	if bus != null:
		bus.scene_entered.emit(StringName(scene_id))


## 进出地宫都要先核对时限：超时清空本轮进度（dungeon_day 保留）并送回北城门
func _enter_dungeon() -> void:
	needs_save = true
	if player.dungeon_expired():
		player.dungeon_clear_progress()
		player.set_location(Rules.dungeon_exit_scene())
		page = Pages.dungeon_timeout_page()
		if bus != null:
			bus.scene_entered.emit(StringName(Rules.dungeon_exit_scene()))
		return
	player.set_location(Rules.dungeon_scene())
	page = Pages.dungeon_page(player)
	if bus != null:
		bus.scene_entered.emit(StringName(Rules.dungeon_scene()))


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
			"shop":
				page = Pages.shop_page(player)
			"smith":
				page = Pages.smith_page(player)
			"trade_market":
				page = Pages.trade_market_page(player, Trade.port_at(scene_id))
			"tavern_rumor":
				page = Pages.tavern_rumor_page(player, Trade.port_at(scene_id))
			"dungeon_keeper":
				_dungeon_keeper()
			_:
				page = Pages.npc_flavor_page(npc, player)
		return
	page = Pages.notice_page("这里什么人也没有。", "back_game", "返回游戏")


# ---------- 战斗 ----------

func _fight(monster_id: String) -> void:
	if not GameData.has_monster(monster_id):
		page = Pages.notice_page("目标不见了。", "back_game", "返回游戏")
		return
	if player.location == Rules.dungeon_scene() and player.dungeon_expired():
		player.dungeon_clear_progress()
		player.set_location(Rules.dungeon_exit_scene())
		needs_save = true
		page = Pages.dungeon_timeout_page()
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
			_handle_win()
		else:
			_handle_defeat()
	else:
		_render_combat("")


## 胜利结算：地宫任务怪计战功 + 总线广播 + 胜利页
func _handle_win() -> void:
	if combat.monster_id == Rules.dungeon_monster() and player.location == Rules.dungeon_scene():
		player.dungeon_add_kill()
	if bus != null:
		bus.enemy_defeated.emit(StringName(combat.monster_id))
		bus.battle_won.emit(StringName(combat.monster_id))
		if combat.reward_item != "":
			bus.item_obtained.emit(StringName(combat.reward_item), 1)
		if combat.reward_equip != "":
			bus.item_obtained.emit(StringName(combat.reward_equip), 1)
		if combat.level_gained > 0:
			bus.leveled_up.emit(player.level)
	page = Pages.win_page(combat, player)


## 战败处理（普通攻击与战斗中用药共用）：清地宫进度 → 回城复活
func _handle_defeat() -> void:
	player.dungeon_clear_progress()
	var lost := Rules.death_loss(player.copper)
	player.take_copper(lost)
	player.heal(Rules.revive_hp(player.max_hp()))
	player.set_location(Rules.revive_scene())
	page = Pages.lose_page(combat, lost, String(GameData.get_scene(player.location).get("name", "")))
	if bus != null:
		bus.battle_lost.emit(StringName(combat.monster_id))
		bus.player_died.emit(StringName(combat.monster_id))


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

## 威尼斯市场成交价（契约 trade-spec §4：_buy/_sell 价源切换为 Trade 引擎，同港零差价）
func _venice_price(item_id: String) -> int:
	return Trade.price(item_id, Trade.VENICE, player.current_day())


## 成交卖价（主进程裁决 trade-spec 遗留项：打怪掉落材料不是贸易品，不做跨港差价）：
## 贸易品（world 各港 specialties/demand_pool 引用集合）→ Trade 引擎本地价；
## 非贸易品带显式 sell_price 字段 → 固定回收价；兜底 → 买价 50%。
func _sell_unit_price(item_id: String, port_id: String = Trade.VENICE) -> int:
	if Trade.trade_goods().has(item_id):
		return Trade.price(item_id, port_id, player.current_day())
	var def := GameData.get_item(item_id)
	if def.has("sell_price"):
		return maxi(int(def.get("sell_price", 0)), 1)
	return Rules.sell_price(int(def.get("buy_price", 0)))


func _buy(item_id: String, qty_text: String) -> void:
	var def := GameData.get_item(item_id)
	var qty := int(qty_text)
	if def.is_empty() or qty <= 0:
		page = Pages.market_main(player)
		return
	var cost := _venice_price(item_id) * qty
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
	var earn := _sell_unit_price(item_id) * qty
	player.add_copper(earn)
	page = Pages.market_result(player, "你卖掉了 %d 箱%s，进账 %d 铜贝。" % [qty, player.item_name(item_id), earn])
	needs_save = true


func count_sell_qty(item_id: String, qty_text: String) -> int:
	return player.count_stack(item_id) if qty_text == "all" else int(qty_text)


# ---------- 港口贸易 / 酒保情报（契约 trade-spec §4-§5） ----------

## 玩家当前所在港口 id（world 数据缺失时返回 ""）
func _trade_port() -> String:
	return Trade.port_at(player.location)


func _trade_buy(good_id: String, qty_text: String) -> void:
	var port_id := _trade_port()
	var qty := int(qty_text)
	var def := GameData.get_item(good_id)
	if port_id == "" or String(def.get("type", "")) != "goods" or qty <= 0:
		page = Pages.trade_market_page(player, port_id)
		return
	var cost := Trade.price(good_id, port_id, player.current_day()) * qty
	var per_weight := int(def.get("weight", 0))
	if per_weight > 0 and player.weight() + per_weight * qty > player.weight_cap():
		page = Pages.trade_market_page(player, port_id, "商人：这么多货你背不动，少进点吧。")
		return
	if not player.spend_copper(cost):
		page = Pages.trade_market_page(player, port_id, "商人：钱不够啊，先去银行折兑了再来，行情可不等人。")
		return
	if not player.add_stack(good_id, qty):
		player.add_copper(cost)
		page = Pages.trade_market_page(player, port_id, "商人：你身上放不下了，先出手一些再来。")
		return
	page = Pages.trade_market_page(player, port_id, "你买下了 %d 箱%s，花费 %d 铜贝。" % [qty, player.item_name(good_id), cost])
	needs_save = true
	if bus != null:
		bus.item_obtained.emit(StringName(good_id), qty)


func _trade_sell(good_id: String, qty_text: String) -> void:
	var port_id := _trade_port()
	var qty := count_sell_qty(good_id, qty_text)
	var def := GameData.get_item(good_id)
	if port_id == "" or String(def.get("type", "")) != "goods" or qty <= 0:
		page = Pages.trade_market_page(player, port_id)
		return
	if not player.remove_stack(good_id, qty):
		page = Pages.trade_market_page(player, port_id, "商人：你哪来那么多货？")
		return
	var earn := _sell_unit_price(good_id, port_id) * qty
	player.add_copper(earn)
	page = Pages.trade_market_page(player, port_id, "你卖掉了 %d 箱%s，进账 %d 铜贝。" % [qty, player.item_name(good_id), earn])
	needs_save = true


## 酒保打听：扣费 → 从当日全部港口热门集合挑 2 条（排除当前港），情报必真
func _rumor() -> void:
	var port_id := _trade_port()
	var cost := Rules.rumor_cost()
	if not player.spend_copper(cost):
		page = Pages.tavern_rumor_page(player, port_id, "酒保：铜板都不掏一枚，还想听我的消息？")
		return
	needs_save = true
	var pool := Trade.rumor_pool(player.current_day(), port_id)
	if pool.is_empty():
		page = Pages.tavern_rumor_result(player, ["酒保（压低声音）：最近海上风平浪静，各港都没什么抢手货，攒着铜板吧。"])
		return
	var first_idx := player.rng.randi() % pool.size()
	var second_idx := first_idx
	if pool.size() > 1:
		second_idx = (first_idx + 1 + player.rng.randi() % (pool.size() - 1)) % pool.size()
	var lines: Array[String] = [_rumor_line(pool[first_idx])]
	if second_idx != first_idx:
		lines.append(_rumor_line(pool[second_idx]))
	page = Pages.tavern_rumor_result(player, lines)


func _rumor_line(entry: Dictionary) -> String:
	return "酒保（压低声音）：【%s】在【%s】最近很抢手，去晚了可就赶不上了……" % [
		player.item_name(String(entry.get("good", ""))),
		Trade.port_name(String(entry.get("port", ""))),
	]


# ---------- 商店 / 药品（扩展契约 §4.1、§4.3） ----------

func _buy_drug(id: String, qty_text: String) -> void:
	var def := GameData.get_item(id)
	var qty := int(qty_text)
	if def.is_empty() or String(def.get("type", "")) != "drug" or qty <= 0:
		page = Pages.shop_page(player)
		return
	var unit := int(def.get("price", int(def.get("buy_price", 0))))
	var cost := unit * qty
	if not player.spend_copper(cost):
		page = Pages.shop_result(player, "商人：%d铜贝都拿不出来？出门在外钱就是命，回银行取了再来。" % cost)
		return
	if not player.add_stack(id, qty):
		player.add_copper(cost)
		page = Pages.shop_result(player, "商人：你身上药都塞不下了，先吃掉几瓶再来。")
		return
	page = Pages.shop_result(player, "你买下了 %d 瓶%s，花费 %d 铜贝。" % [qty, player.item_name(id), cost])
	needs_save = true
	if bus != null:
		bus.item_obtained.emit(StringName(id), qty)


func _use_drug(id: String) -> void:
	var msg := ""
	match player.use_drug(id):
		"":
			needs_save = true
			msg = "你服下了%s，体力恢复到 %d/%d，浑身是劲。" % [player.item_name(id), player.hp_cur, player.max_hp()]
		"full":
			msg = "你现在体力充沛，不用吃药，留着救急吧。"
		_:
			msg = "你翻遍背包也没找到这种药。"
	page = Pages.drug_result(player, msg)


# ---------- 铁匠（扩展契约 §4.4） ----------

func _repair_hand() -> void:
	var inst := player.hand_item()
	if inst.is_empty():
		page = Pages.smith_result(player, "铁匠：你两手空空，让我修什么？先去打造一件吧。")
		return
	var missing := player.hand_missing_dur()
	if missing <= 0:
		page = Pages.smith_result(player, "铁匠：你这把武器好端端的，修什么修？")
		return
	var cost := Rules.repair_cost(missing)
	if not player.spend_copper(cost):
		page = Pages.smith_result(player, "铁匠：修这 %d 点缺口要 %d 铜贝，你钱不够，攒攒再来。" % [missing, cost])
		return
	var name := player.item_name(String(inst.get("id", "")))
	player.repair_hand()
	page = Pages.smith_result(player, "铁匠：叮叮当当一阵锤，「%s」的耐久补满了，收你 %d 铜贝。" % [name, cost])
	needs_save = true


func _forge(id: String) -> void:
	var def := GameData.get_item(id)
	var forge: Dictionary = def.get("forge", {})
	if def.is_empty() or forge.is_empty():
		page = Pages.forge_page(player)
		return
	var mats: Dictionary = forge.get("materials", {})
	var missing := ""
	for mid: String in mats:
		var need := int(mats[mid])
		if player.count_stack(mid) < need:
			missing += "%s×%d " % [player.item_name(mid), need - player.count_stack(mid)]
	if missing != "":
		page = Pages.smith_result(player, "铁匠：材料不齐，还缺 %s，凑齐了再来。" % missing.strip_edges())
		return
	var cost := int(forge.get("copper", 0))
	if not player.spend_copper(cost):
		page = Pages.smith_result(player, "铁匠：工钱 %d 铜贝都凑不出来？去去去，攒够了再来。" % cost)
		return
	for mid: String in mats:
		player.remove_stack(mid, int(mats[mid]))
	if player.add_equip(id) < 0:
		for mid: String in mats:
			player.add_stack(mid, int(mats[mid]))
		player.add_copper(cost)
		page = Pages.smith_result(player, "铁匠：你包都塞满了，装备往哪儿放？腾个地方再来。")
		return
	page = Pages.smith_result(player, "铁匠：好一件「%s」！火候正好，拿去试试身手。" % player.item_name(id))
	needs_save = true
	if bus != null:
		bus.item_obtained.emit(StringName(id), 1)


# ---------- 威尼斯地宫（扩展契约 §4.5） ----------

func _dungeon_try() -> void:
	if not GameData.has_scene(Rules.dungeon_scene()):
		page = Pages.notice_page("威尼斯地宫：暂未开发区域，请耐心等待", "back_game", "返回")
		return
	match player.dungeon_try_enter():
		"":
			_enter_dungeon()
		"level":
			var range_lv := Rules.dungeon_level_range()
			page = Pages.notice_page("探险官：你的级别不在 %d-%d 级之内，地宫的规矩不能破。" % [range_lv.x, range_lv.y], "back_game", "返回")
		_:
			page = Pages.notice_page("探险官：今天你已经进过一次地宫了，地宫一日一开，明天再来吧。", "back_game", "返回")


func _dungeon_keeper() -> void:
	if player.dungeon_kills < Rules.dungeon_kill_goal():
		page = Pages.dungeon_keeper_page(player)
		return
	var copper_reward := Rules.dungeon_reward_copper()
	var gold_reward := Rules.dungeon_reward_gold()
	player.add_copper(copper_reward)
	player.add_gold(gold_reward)
	player.dungeon_clear_progress()
	needs_save = true
	page = Pages.dungeon_reward_page(copper_reward, gold_reward)
	if bus != null:
		bus.dungeon_cleared.emit(copper_reward, gold_reward)


# ---------- 战斗中用药（扩展契约 §4.2） ----------

func _combat_drug_page() -> void:
	if combat == null or combat.finished:
		_back_game()
		return
	page = Pages.combat_drug_page(combat, player)


func _combat_use(drug_id: String) -> void:
	if combat == null or combat.finished:
		_back_game()
		return
	var hp_before := player.hp_cur
	match player.use_drug(drug_id):
		"none":
			_render_combat("你翻遍背包也没找到这种药。")
			return
		"full":
			_render_combat("你现在体力充沛，先省着点药。")
			return
	var healed := player.hp_cur - hp_before
	combat.monster_counter(player)
	needs_save = true
	if combat.finished and not combat.won:
		_handle_defeat()
		return
	_render_combat("你服下了%s，体力+%d。" % [player.item_name(drug_id), healed])


# ---------- 码头 / 传送 ----------

## 传送出海（契约 trade-spec §6）：world 就位后真实扣费跨港；缺失沿用原占位文案
func _tp(arg: String) -> void:
	var idx := int(arg)
	if GameData.world_ports.is_empty():
		if idx < 0 or idx >= GameData.ports.size():
			page = Pages.teleport_page(player)
			return
		# 原版除威尼斯外所有港口均未实现：占位文案逐字保留
		page = Pages.notice_page("%s：暂未开发区域，请耐心等待" % GameData.ports[idx], "teleport", "返回码头")
		return
	if idx < 0 or idx >= GameData.world_ports.size():
		page = Pages.teleport_page(player)
		return
	var port: Dictionary = GameData.world_ports[idx]
	var port_id := String(port.get("id", ""))
	var scene_id := String(port.get("scene", port_id))
	if not GameData.has_scene(scene_id):
		# world 已列港但场景尚未实装：保持占位，不扣费
		page = Pages.notice_page("%s：暂未开发区域，请耐心等待" % String(port.get("name", port_id)), "teleport", "返回码头")
		return
	if Trade.port_at(player.location) == port_id:
		page = Pages.notice_page("船老板：你就站在%s的地界上，坐什么船？先去别处发财吧。" % String(port.get("name", port_id)), "teleport", "返回传送")
		return
	var cost := Rules.teleport_cost_copper()
	if not player.spend_copper(cost):
		page = Pages.notice_page("船老板：就带这几个铜子儿也想跨海？船票 %d 铜贝，去银行折兑了再来。" % cost, "teleport", "返回传送")
		return
	player.set_location(scene_id)
	page = Pages.tp_arrival_page(String(port.get("name", port_id)), cost)
	needs_save = true
	if bus != null:
		bus.scene_entered.emit(StringName(scene_id))


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


## 铁匠回收装备（契约 trade-spec §7）：手持先自动卸下，按基准价 40% 入账
func _sell_equip(idx: int) -> void:
	var inst := player.sell_equip(idx)
	if inst.is_empty():
		page = Pages.sell_equip_page(player)
		return
	var id := String(inst.get("id", ""))
	var earn := Rules.equip_sell_price(int(GameData.get_item(id).get("price", 0)))
	player.add_copper(earn)
	page = Pages.smith_result(player, "铁匠：成，「%s」回炉我收了，%d 铜贝拿好，别弄丢了。" % [player.item_name(id), earn])
	needs_save = true
