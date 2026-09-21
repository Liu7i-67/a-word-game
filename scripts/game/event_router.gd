class_name EventRouter
extends RefCounted
## 事件分发器（对应原版「_简单超文本框1_自定义超链接被单击」主事件分发）。
## handle(event) → 校验/改状态（经 PlayerCore）→ 生成新 BBCode 页面。
## UI 层只读 page / input_mode / needs_save / toast，不直接改游戏状态。

signal game_started
signal continue_requested
signal update_check_requested
signal page_changed

var player: PlayerCore
var bus: Variant = null

var page: String = ""
var input_mode: String = ""
var needs_save := false

var combat: CombatEngine = null
var _combat_show_self := false

## GM 彩蛋密码盘当前输入（仅 UI 会话内临时状态，不入存档）
var gm_pwd := ""

## 检查更新结果里的下载入口（update_download 事件用）
var _update_apk_url := ""
var _update_html_url := ""


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
		"check_update":
			_check_update()
		"update_download":
			_update_download()
		"back_title":
			page = Pages.intro_title(_has_save())
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
		"gm_password":
			gm_pwd = ""
			page = Pages.gm_password_page(gm_pwd)
		"gm_pwd":
			_gm_pwd_input(arg)
		"gm_pwd_ok":
			_gm_pwd_ok()
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
		"sell_equip_all":
			_sell_equip_all(arg)
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
		"use_item":
			_use_item(arg)
		"meditate":
			_meditate()
		"fish":
			_fish(arg == "bait")
		"dive":
			_dive()
		"farm":
			page = Pages.farm_page(player)
		"farm_plant":
			_farm_plant(int(arg))
		"farm_harvest":
			_farm_harvest()
		"wild_tp":
			_wild_tp(arg)
		"worldmap":
			page = Pages.worldmap_page(player)
		"smith_enhance":
			_smith_enhance(arg)
		"smith_gem":
			_smith_gem(arg, arg2)
		"alchemy":
			_alchemy(int(arg))
		"circus_sell":
			_circus_sell(arg, arg2)
		"buy_equip":
			_buy_equip(arg)
		"equip_armor":
			_equip_armor(int(arg))
		"armor_off":
			_armor_off(int(arg))
		"quest_andrew":
			_quest_andrew(arg)
		"quest_siren":
			_quest_siren()
		"riddle":
			_riddle(int(arg))
		"skill_cast":
			_skill_cast()
		"gift_claim":
			_gift_claim()
		"rename":
			_rename_submit(param)
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


# ---------- 检查更新（标题页入口；网络经 UpdateChecker，装配在 Main） ----------

func _check_update() -> void:
	page = Pages.update_checking_page()
	update_check_requested.emit()


## UpdateChecker 完成后由 Main 回填：渲染结果页并广播 page_changed 让界面重绘
func apply_update_result(result: Dictionary) -> void:
	_update_apk_url = String(result.get("apk_url", ""))
	_update_html_url = String(result.get("html_url", ""))
	var local := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	page = Pages.update_result_page(result, local)
	page_changed.emit()


## 前往下载：系统浏览器打开 APK 直链（无直链退回发布页）；页面保持不动
func _update_download() -> void:
	var url := _update_apk_url if _update_apk_url != "" else _update_html_url
	if url != "":
		OS.shell_open(url)


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
			# 契约 plan-v2 §3 新 kind 全集
			"tavern":
				page = Pages.tavern_page(scene, player)
			"circus":
				page = Pages.circus_page(player, npc)
			"alchemist":
				page = Pages.alchemy_page(player)
			"trainer":
				page = Pages.trainer_page(player, npc)
			"siren":
				page = Pages.siren_page(player, npc)
			"riddle":
				page = Pages.riddle_page(player, npc)
			_:
				page = Pages.npc_flavor_page(npc, player)
		return
	page = Pages.notice_page("这里什么人也没有。", "back_game", "返回游戏")


## 当前场景第一个指定 kind 的 NPC（找不到返回 {}）
func _npc_by_kind(kind: String) -> Dictionary:
	for npc: Dictionary in GameData.get_scene(player.location).get("npcs", []):
		if String(npc.get("kind", "")) == kind:
			return npc
	return {}


# ---------- 战斗 ----------

## 当前场景第一个可战斗对象的怪物 id（无则 ""）——自动战斗入口判定用
func scene_first_monster() -> String:
	var monsters: Array = GameData.get_scene(player.location).get("monsters", [])
	for m: Dictionary in monsters:
		var id := String(m.get("id", ""))
		if GameData.has_monster(id):
			return id
	return ""


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


## 胜利结算：地宫任务怪计战功 + 安德鲁试炼野外击杀计数 + 总线广播 + 胜利页
func _handle_win() -> void:
	if combat.monster_id == Rules.dungeon_monster() and player.location == Rules.dungeon_scene():
		player.dungeon_add_kill()
	# 安德鲁试炼（契约 plan-v2 §5.5）：每日 active 期间累计野外击杀（dungeon 不计）
	var qa: Dictionary = player.quest_andrew
	if String(qa.get("state", "")) == "active" and int(qa.get("day", -1)) == player.current_day() \
			and player.location != Rules.dungeon_scene():
		qa["kills"] = int(qa.get("kills", 0)) + 1
		player.quest_andrew = qa
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
	player.reset_streak()  # 契约 plan-v2 §4.2：撤退视为中断连胜（E1 引擎侧无法区分，由 router 落笔）
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


# ---------- GM 彩蛋（福利官暗号） ----------

## 密码盘按键：数字追加（满 6 位忽略），clear 清空
func _gm_pwd_input(key: String) -> void:
	if key == "clear":
		gm_pwd = ""
	elif key.length() == 1 and key >= "1" and key <= "9" and gm_pwd.length() < 6:
		gm_pwd += key
	page = Pages.gm_password_page(gm_pwd)


## 确认：密码正确发奖（可重复触发）；错误或没输满 6 位一律无提示退回福利官
func _gm_pwd_ok() -> void:
	var code := gm_pwd
	gm_pwd = ""
	if code != Rules.gm_password():
		page = Pages.welfare_page(player)
		return
	var pill_id := Rules.gm_exp_pill()
	var pill_count := Rules.gm_exp_pill_count()
	if pill_id == "" or not GameData.has_item(pill_id) or not player.add_stack(pill_id, pill_count):
		pill_count = 0
	var knife_id := Rules.gm_knife()
	var knife_given := ""
	if knife_id != "" and GameData.has_item(knife_id):
		if player.add_equip(knife_id) >= 0 or player.add_stack(knife_id, 1):
			knife_given = knife_id
	needs_save = true
	page = Pages.gm_reward_page(player, pill_id, pill_count, knife_given)
	if bus != null:
		if pill_count > 0:
			bus.item_obtained.emit(StringName(pill_id), pill_count)
		if knife_given != "":
			bus.item_obtained.emit(StringName(knife_id), 1)


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
	var t := String(def.get("type", ""))
	var price := int(def.get("price", 0))
	# 契约 plan-v2 §2.1：商店在售=药品 + price>0 的功能道具（任务物品/礼包除外）
	var eff: Dictionary = def.get("effect", {})
	var kind := String(eff.get("kind", ""))
	var sellable := price > 0 and ((t == "drug") or (t == "item" and kind != "quest_item" and kind != "gift"))
	if def.is_empty() or not sellable or qty <= 0:
		page = Pages.shop_page(player)
		return
	# 限持道具（体力宝等，契约 §5.1）：bag 持有数不得超过 limit
	var limit := int(def.get("limit", 0))
	if limit > 0 and player.count_stack(id) + qty > limit:
		page = Pages.shop_result(player, "商人：%s每人限持 %d 个，你身上的已经够多了。" % [player.item_name(id), limit])
		return
	var cost := price * qty
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
			msg = _drug_used_msg(id)
		"full":
			msg = "你现在体力充沛，不用吃药，留着救急吧。"
		_:
			msg = "你翻遍背包也没找到这种药。"
	page = Pages.drug_result(player, msg)


## 用药成功后的结果文案：加速丹报 buff 场次，体力药报恢复量
func _drug_used_msg(id: String) -> String:
	var def := GameData.get_item(id)
	if def.has("exp_buff"):
		var buff: Dictionary = def.get("exp_buff", {})
		return "你服下了%s，接下来 %d 场战斗，战斗结束后的经验结算×%d。" % [
			player.item_name(id), int(buff.get("battles", 10)), int(buff.get("multiplier", 10))]
	return "你服下了%s，体力恢复到 %d/%d，浑身是劲。" % [player.item_name(id), player.hp_cur, player.max_hp()]


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
	if GameData.get_item(drug_id).has("exp_buff"):
		# 加速丹不回体力：不算回合动作，怪物不还手（use_drug 对 buff 丹只会返回 ""/none）
		if player.use_drug(drug_id) != "":
			_render_combat("你翻遍背包也没找到这种药。")
			return
		needs_save = true
		_render_combat(_drug_used_msg(drug_id))
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


## 铁匠回收装备（契约 trade-spec §7）：手持先自动卸下，按基准价 40% 入账。
## 成交后留在出售页（带成交提示继续出售），省去「返回铁匠铺→出售装备」往返。
## 绑定装备不可出售回收（契约 plan-v2 主进程裁决）
func _sell_equip(idx: int) -> void:
	if idx >= 0 and idx < player.equips.size() and bool((player.equips[idx] as Dictionary).get("bound", false)):
		page = Pages.sell_equip_page(player, "绑定装备无法出售——它已经认主了。")
		return
	var inst := player.sell_equip(idx)
	if inst.is_empty():
		page = Pages.sell_equip_page(player)
		return
	var id := String(inst.get("id", ""))
	var earn := Rules.equip_sell_price(int(GameData.get_item(id).get("price", 0)))
	player.add_copper(earn)
	page = Pages.sell_equip_page(player, "铁匠：成，「%s」回炉我收了，%d 铜贝拿好，别弄丢了。还有要出的吗？" % [
		player.item_name(id), earn])
	needs_save = true


## 批量回收全部同名装备：倒序移除（sell_equip 内部处理手持下标前移）；绑定件一律不收
func _sell_equip_all(id: String) -> void:
	if not GameData.has_item(id):
		page = Pages.sell_equip_page(player)
		return
	var unit := Rules.equip_sell_price(int(GameData.get_item(id).get("price", 0)))
	var count := 0
	var bound_seen := false
	for i in range(player.equips.size() - 1, -1, -1):
		var inst: Dictionary = player.equips[i]
		if String(inst.get("id", "")) != id:
			continue
		if bool(inst.get("bound", false)):
			bound_seen = true
			continue
		player.sell_equip(i)
		count += 1
	if count == 0:
		if bound_seen:
			page = Pages.sell_equip_page(player, "绑定装备无法出售——它已经认主了。")
		else:
			page = Pages.sell_equip_page(player)
		return
	var earn := unit * count
	player.add_copper(earn)
	page = Pages.sell_equip_page(player, "铁匠：成，%d件「%s」回炉我全收了，%d 铜贝拿好，别弄丢了。" % [
		count, player.item_name(id), earn])
	needs_save = true


# ---------- 通用使用道具（契约 plan-v2 §3 use_item，按 effect kind 分发） ----------

func _use_item(id: String) -> void:
	var def := GameData.get_item(id)
	if def.is_empty() or player.count_stack(id) <= 0:
		page = Pages.notice_page("你翻遍背包也没找到这件东西。", "items:other", "返回")
		return
	var eff: Dictionary = def.get("effect", {})
	match String(eff.get("kind", "")):
		"stamina":
			if player.stamina >= player.max_stamina():
				page = Pages.item_used_page(player, "%s先收好——现在活力满满，喝了也是浪费。" % player.item_name(id))
				return
			var before := player.stamina
			player.gain_stamina(maxi(int(eff.get("value", 0)), 0))
			player.remove_stack(id, 1)
			needs_save = true
			page = Pages.item_used_page(player, "你使用了%s，生活体力 +%d（当前 %d/%d）。" % [
				player.item_name(id), player.stamina - before, player.stamina, player.max_stamina()])
		"exp_buff":
			player.add_time_buff("exp_buff", float(eff.get("hours", 1.0)), float(eff.get("multiplier", 2.0)))
			player.remove_stack(id, 1)
			needs_save = true
			page = Pages.item_used_page(player, "你激活了%s：%d 小时内所有经验来源 +%d%%（同类卡片不可叠加）。" % [
				player.item_name(id), maxi(int(eff.get("hours", 1)), 1),
				int(round((float(eff.get("multiplier", 2.0)) - 1.0) * 100.0))])
		"clear_buff":
			player.clear_buffs()
			player.remove_stack(id, 1)
			needs_save = true
			page = Pages.item_used_page(player, "你撕碎%s，所有卡片效果一扫而空。" % player.item_name(id))
		"weight":
			var extra := maxi(int(eff.get("value", 0)), 0)
			player.weight_bonus += extra
			player.remove_stack(id, 1)
			needs_save = true
			page = Pages.item_used_page(player, "你打开%s，背包负重上限 +%d（当前 %d/%d）。" % [
				player.item_name(id), extra, player.weight(), player.weight_max()])
		"rename":
			input_mode = "rename"
			page = Pages.rename_page(player)
		"teleport_wild":
			page = Pages.wild_tp_page(player)
		"gift":
			_open_gift(id, eff)
		"skill":
			var skill := String(eff.get("skill", "attack"))
			if player.learn_skill(skill):
				player.remove_stack(id, 1)
				needs_save = true
				page = Pages.item_used_page(player, "你研读%s，学会了「攻击术」！战斗中可以施展了。" % player.item_name(id))
			else:
				page = Pages.item_used_page(player, "你已经学会攻击术了，这本技能书用不上了。")
		"meditate_tool":
			page = Pages.item_used_page(player, "你把野球草人立在跟前比划了两下——打坐的法门已在心中。到安静无怪的地方点「打坐」即可修行。")
		"bait":
			page = Pages.item_used_page(player, "小鱼活饵要在钓鱼时选用：钓鱼入口选「用活饵钓鱼」，渔获会好上不少。")
		"seed":
			page = Pages.item_used_page(player, "种子要种到地里才能生根——去农场的田里「播种」吧。")
		"quest_item":
			page = Pages.item_used_page(player, "%s隐隐发光——这是重要的任务信物，不可使用，更不可转卖。" % player.item_name(id))
		_:
			if String(def.get("type", "")) == "drug":
				_use_drug(id)  # heal 类道具走既有 drug 语义（契约：stamina/heal 走 drug 语义）
				return
			page = Pages.item_used_page(player, "你摆弄了半天%s，没发现它能怎么用。" % player.item_name(id))


## 打开礼包（契约 §5.7）：按 effect.contents 发放（copper + 物品）
func _open_gift(id: String, eff: Dictionary) -> void:
	var contents: Dictionary = eff.get("contents", {})
	var got: Array[String] = []
	var copper := int(contents.get("copper", 0))
	if copper > 0:
		player.add_copper(copper)
		got.append("铜贝 +%d" % copper)
	for cid: String in contents:
		if cid == "copper":
			continue
		var n := int(contents[cid])
		if player.add_stack(cid, n):
			got.append("%s ×%d" % [player.item_name(cid), n])
		else:
			got.append("%s ×%d（背包塞不下，散落了……）" % [player.item_name(cid), n])
	player.remove_stack(id, 1)
	needs_save = true
	page = Pages.gift_result(player, got)
	if bus != null:
		for cid: String in contents:
			if cid != "copper":
				bus.item_obtained.emit(StringName(cid), int(contents[cid]))


# ---------- 生活玩法（契约 plan-v2 §5.1-§5.4） ----------

func _meditate() -> void:
	var res := Life.meditate(player)
	needs_save = bool(res.get("ok", false))
	page = Pages.meditate_result(player, res)


func _fish(use_bait: bool) -> void:
	if not Rules.life_fish_scenes().has(player.location):
		page = Pages.notice_page("这里钓不了鱼——去找海滩、浅海、暗礁或码头边的水域吧。", "back_game", "返回")
		return
	var res := Life.fish(player, use_bait)
	needs_save = bool(res.get("ok", false))
	page = Pages.fish_result(player, res, use_bait)


func _dive() -> void:
	if not Rules.life_dive_scenes().has(player.location):
		page = Pages.notice_page("这里没法潜水——浅海和暗礁的水才够深。", "back_game", "返回")
		return
	var res := Life.dive(player)
	var monster_id := String(res.get("monster_id", ""))
	if monster_id != "":
		# 潜水遇袭：由 router 起 CombatEngine 进战斗（契约 §4.3）
		needs_save = true
		combat = CombatEngine.new(monster_id, player)
		_combat_show_self = false
		_render_combat(String(res.get("msg", "水下暗流涌动——")))
		return
	# 拾得海皇碎片：入包 + 碎片计数（契约 §5.4）
	if bool(res.get("ok", false)) and String(res.get("item_id", "")) == Pages.SIREN_SHARD_ID:
		player.quest_siren["shards"] = int(player.quest_siren.get("shards", 0)) + 1
	needs_save = bool(res.get("ok", false))
	page = Pages.dive_result(player, res)


func _farm_plant(slot: int) -> void:
	if player.location != Pages.FARM_SCENE:
		page = Pages.notice_page("种子只能在农场的田里播种。", "back_game", "返回")
		return
	var seed_id := _first_effect_item("seed")
	if seed_id == "":
		page = Pages.farm_page(player, "你包里没有种子——去商店买些牧草种子吧。")
		return
	var cost := Rules.life_farm_stamina()
	if player.stamina < cost:
		page = Pages.farm_page(player, "体力不足（播种要 %d 点），歇会再来。" % cost)
		return
	var res := player.plant_plot(slot, seed_id, int(Time.get_unix_time_from_system()))
	if bool(res.get("ok", false)):
		player.spend_stamina(cost)
		needs_save = true
	page = Pages.farm_page(player, String(res.get("msg", "")))


func _farm_harvest() -> void:
	if player.location != Pages.FARM_SCENE:
		page = Pages.notice_page("庄稼在农场的田里，回农场才能收获。", "back_game", "返回")
		return
	var now := int(Time.get_unix_time_from_system())
	var matured := 0
	var unripe := 0
	for i in player.farm_plots.size():
		var res := player.harvest_plot(i, now)
		if bool(res.get("ok", false)):
			matured += 1
		elif String(res.get("msg", "")).contains("还没成熟"):
			unripe += 1
	var notice := ""
	if matured > 0:
		needs_save = true
		notice = "收获了 %d 块田的庄稼！" % matured
	if unripe > 0:
		notice += ("；" if notice != "" else "") + "%d 块田的庄稼还没成熟，再等等。" % unripe
	if notice == "":
		notice = "田都空着，先播种吧。"
	page = Pages.farm_page(player, notice)


## 引路蜂传送（契约 §5.9）：消耗一只，瞬移到列表内野外场景
func _wild_tp(scene_id: String) -> void:
	if player.count_stack(Pages.TP_BEE_ID) <= 0:
		page = Pages.wild_tp_page(player, "引路蜂用完了，没有它可找不到路。")
		return
	if not Pages.wild_scenes().has(scene_id):
		page = Pages.wild_tp_page(player, "引路蜂对着那个方向转了几圈，嗡嗡直叫——去不得。")
		return
	if scene_id == player.location:
		page = Pages.wild_tp_page(player, "你就站在这儿呢。")
		return
	player.remove_stack(Pages.TP_BEE_ID, 1)
	combat = null
	player.set_location(scene_id)
	page = Pages.scene_page(player, scene_id)
	needs_save = true
	if bus != null:
		bus.scene_entered.emit(StringName(scene_id))


# ---------- 铁匠强化 / 宝石 / 炼金 / 装备购买 / 护甲（契约 plan-v2 §5） ----------

func _smith_enhance(arg: String) -> void:
	if arg == "":
		page = Pages.smith_enhance_page(player)
		return
	var idx := int(arg)
	if idx < 0 or idx >= player.equips.size():
		page = Pages.smith_enhance_page(player, "没有这件装备。")
		return
	var res := player.enhance_equip(idx)
	needs_save = bool(res.get("ok", false))
	page = Pages.smith_enhance_page(player, String(res.get("msg", "")))


func _smith_gem(arg: String, arg2: String) -> void:
	if arg == "":
		page = Pages.smith_gem_page(player, -1)
		return
	var idx := int(arg)
	if idx < 0 or idx >= player.equips.size():
		page = Pages.smith_gem_page(player, -1, "没有这件装备。")
		return
	if arg2 == "":
		page = Pages.smith_gem_page(player, idx)
		return
	var res := player.socket_gem(idx, arg2)
	needs_save = bool(res.get("ok", false))
	page = Pages.smith_gem_page(player, idx, String(res.get("msg", "")))


## 炼金兑换（契约 §5：按 config.smith.alchemy 配方，校验材料与铜贝）
func _alchemy(idx: int) -> void:
	var recipes := Rules.smith_alchemy()
	if idx < 0 or idx >= recipes.size():
		page = Pages.alchemy_page(player)
		return
	var recipe: Dictionary = recipes[idx]
	var give: Dictionary = recipe.get("give", {})
	var get_d: Dictionary = recipe.get("get", {})
	var missing := ""
	for mid: String in give:
		if mid == "copper":
			continue
		var lack := int(give[mid]) - player.count_stack(mid)
		if lack > 0:
			missing += "%s×%d " % [player.item_name(mid), lack]
	var copper := int(give.get("copper", 0))
	if missing != "":
		page = Pages.alchemy_page(player, "助手：材料不齐，还缺 %s，凑齐了再来。" % missing.strip_edges())
		return
	if not player.spend_copper(copper):
		page = Pages.alchemy_page(player, "助手：%d 铜贝都拿不出来？炼金的火可等不起。" % copper)
		return
	for mid: String in give:
		if mid != "copper":
			player.remove_stack(mid, int(give[mid]))
	var gid := String(get_d.get("id", ""))
	var gn := maxi(int(get_d.get("n", 1)), 1)
	if not player.add_stack(gid, gn):
		# 入包失败整体回滚（材料与铜贝退还），不吞玩家材料
		for mid: String in give:
			if mid == "copper":
				player.add_copper(int(give[mid]))
			else:
				player.add_stack(mid, int(give[mid]))
		page = Pages.alchemy_page(player, "助手：你包都满了，炼好的东西没地方放。")
		return
	needs_save = true
	page = Pages.alchemy_page(player, "助手：炉火正好——%s×%d 炼好了，拿稳别摔了。" % [player.item_name(gid), gn])


## 铁匠购买装备（契约 §2.1：price>0 装备在铁匠处在售）
func _buy_equip(id: String) -> void:
	var def := GameData.get_item(id)
	if def.is_empty() or String(def.get("type", "")) != "equip" or int(def.get("price", 0)) <= 0:
		page = Pages.smith_page(player)
		return
	var cost := int(def.get("price", 0))
	if not player.spend_copper(cost):
		page = Pages.smith_result(player, "铁匠：%d 铜贝都拿不出来？想清楚了再来。" % cost)
		return
	if player.add_equip(id) < 0:
		player.add_copper(cost)
		page = Pages.smith_result(player, "铁匠：你身上装备塞满了，腾个地方再来。")
		return
	page = Pages.smith_result(player, "铁匠：「%s」拿好，钱货两讫。" % player.item_name(id))
	needs_save = true
	if bus != null:
		bus.item_obtained.emit(StringName(id), 1)


func _equip_armor(idx: int) -> void:
	if idx < 0 or idx >= player.equips.size():
		page = Pages.items_page(player, "equip")
		return
	if not player.equip_armor(idx):
		page = Pages.notice_page("这件护甲穿不上（等级不足、已损坏，或它不是护甲）。", "equip_view:%d" % idx, "返回")
		return
	needs_save = true
	page = Pages.equip_detail(player, idx)


func _armor_off(idx: int) -> void:
	player.unequip_armor()
	needs_save = true
	page = Pages.equip_detail(player, idx)


# ---------- 任务链 / 谜语（契约 plan-v2 §5.5-§5.6） ----------

## 安德鲁试炼：accept/claim 每日轮换（day 参照 dungeon_day 的当日序号）
func _quest_andrew(arg: String) -> void:
	var npc := _npc_by_kind("trainer")
	var today := player.current_day()
	if player.has_skill("attack"):
		page = Pages.trainer_page(player, npc, "安德鲁：你都会攻击术了，还来做什么？去海阔天空处历练吧。")
		return
	match arg:
		"accept":
			var qa: Dictionary = player.quest_andrew
			if int(qa.get("day", -1)) == today and String(qa.get("state", "")) != "":
				page = Pages.trainer_page(player, npc, "安德鲁：今天的试炼已经有安排了，明天再来接新的。")
			else:
				player.quest_andrew = {"state": "active", "kills": 0, "day": today}
				needs_save = true
				page = Pages.trainer_page(player, npc, "安德鲁：好胆识！击杀 %d 只野外野怪再来找我。（地宫的杀戮不算数）" % Rules.quest_andrew_kills())
		"claim":
			var qa: Dictionary = player.quest_andrew
			var kills := int(qa.get("kills", 0))
			if String(qa.get("state", "")) != "active" or int(qa.get("day", -1)) != today:
				page = Pages.trainer_page(player, npc, "安德鲁：先把今天的试炼接下再说。")
			elif kills < Rules.quest_andrew_kills():
				page = Pages.trainer_page(player, npc, "安德鲁：才 %d 只？还差 %d 只，回来别想领赏。" % [
					kills, Rules.quest_andrew_kills() - kills])
			elif not player.add_stack("jineng_shu", 1):
				page = Pages.trainer_page(player, npc, "安德鲁：你包都满了，技能书没地方放，腾个位置再来。")
			else:
				var reward := Rules.quest_andrew_reward_copper()
				player.add_copper(reward)
				player.quest_andrew = {"state": "claimed", "kills": kills, "day": today}
				needs_save = true
				page = Pages.trainer_page(player, npc, "安德鲁：说话算话——《技能书-攻击术》和 %d 铜贝都归你。去「物品→其他」研读技能书即可学会攻击术。" % reward)
		_:
			page = Pages.trainer_page(player, npc)


## 西利亚海皇碎片：集 3 交付换谢礼（一次性）
func _quest_siren() -> void:
	var npc := _npc_by_kind("siren")
	if bool(player.quest_siren.get("claimed", false)):
		page = Pages.siren_page(player, npc, "西利亚：谢礼已经给过你了，莫要贪心。")
		return
	var need := Rules.quest_siren_shards()
	var have := player.count_stack(Pages.SIREN_SHARD_ID)
	if have < need:
		page = Pages.siren_page(player, npc, "西利亚：碎片还凑不齐（%d/%d），海底再见。" % [have, need])
		return
	# 预检负重：谢礼不可复原，交付途中不许散落
	var reward := Rules.quest_siren_reward()
	var need_weight := 0
	for rid: String in reward:
		need_weight += int(GameData.get_item(rid).get("weight", 0)) * int(reward[rid])
	if player.weight() + need_weight > player.weight_max():
		page = Pages.siren_page(player, npc, "西利亚：你包都塞满了，谢礼没法给你——腾出地方再来。")
		return
	player.remove_stack(Pages.SIREN_SHARD_ID, need)
	var got: Array[String] = []
	for rid: String in reward:
		var n := int(reward[rid])
		player.add_stack(rid, n)
		got.append("%s×%d" % [player.item_name(rid), n])
	player.quest_siren["claimed"] = true
	needs_save = true
	page = Pages.siren_page(player, npc, "西利亚：海皇向勇士致意！谢礼收好——%s。" % "、".join(got))


## 奥布帕斯谜语：每日一题（riddle_day 记当日），答对 500 铜，答错可再猜
func _riddle(opt_idx: int) -> void:
	var npc := _npc_by_kind("riddle")
	var today := player.current_day()
	if player.riddle_day == today:
		page = Pages.riddle_page(player, npc, "奥布帕斯：今日的赏钱已经给过你了，明天再来。")
		return
	var options := Pages.riddle_options()
	if opt_idx < 0 or opt_idx >= options.size():
		page = Pages.riddle_page(player, npc)
		return
	var riddles := Rules.quest_riddles()
	var riddle: Dictionary = riddles[Pages.riddle_day_index(today)]
	if options[opt_idx] == String(riddle.get("a", "")):
		player.riddle_day = today
		var reward := Rules.quest_riddle_reward_copper()
		player.add_copper(reward)
		needs_save = true
		page = Pages.riddle_page(player, npc, "奥布帕斯：妙哉！正是「%s」。这 %d 铜贝是你的了，明日再来。" % [
			String(riddle.get("a", "")), reward])
	else:
		page = Pages.riddle_page(player, npc, "奥布帕斯：「%s」？哈哈，差远了。再想想，猜错不收钱。" % options[opt_idx])


# ---------- 战斗技能 / 礼包 / 改名（契约 plan-v2 §5.7-§5.8） ----------

## 攻击术（战斗中）：调 CombatEngine.cast_skill（内部扣体力、本场限一次）
func _skill_cast() -> void:
	if combat == null or combat.finished:
		_back_game()
		return
	var res := combat.cast_skill(player)
	if not bool(res.get("ok", false)):
		_render_combat(String(res.get("msg", "")))
		return
	needs_save = true
	if combat.finished:
		if combat.won:
			_handle_win()
		else:
			_handle_defeat()
	else:
		_render_combat("")


## 德罗西动物皮收购（契约 plan-v2 §5.10）：鹅毛/狼皮按市场卖价 120% 现收
func _circus_sell(id: String, qty_text: String) -> void:
	if not Pages.CIRCUS_SKINS.has(id):
		page = Pages.circus_page(player, _npc_by_kind("circus"))
		return
	var qty := count_sell_qty(id, qty_text)
	var have := player.count_stack(id)
	if qty <= 0 or have <= 0:
		page = Pages.circus_page(player, _npc_by_kind("circus"), "德罗西：你手上哪来的皮子？")
		return
	qty = mini(qty, have)
	var unit := Pages.circus_unit_price(id)
	if not player.remove_stack(id, qty):
		page = Pages.circus_page(player, _npc_by_kind("circus"), "德罗西：你手上哪来的皮子？")
		return
	var earn := unit * qty
	player.add_copper(earn)
	needs_save = true
	page = Pages.circus_page(player, _npc_by_kind("circus"),
		"德罗西：皮子我收了——%d张，%d 铜贝点好。动物们就盼着新垫子。" % [qty, earn])


## 福利院预约礼包：一次性领取 yufu_libao×1（打开走 use_item 的 gift 分支）
func _gift_claim() -> void:
	if player.gift_claimed:
		page = Pages.notice_page("福利官：预约礼包你已经领过了，一人只有一份。", "back_game", "返回")
		return
	if not player.add_stack("yufu_libao", 1):
		page = Pages.notice_page("福利官：你包都满了，礼包没地方放——腾个位置再来。", "back_game", "返回")
		return
	player.gift_claimed = true
	needs_save = true
	page = Pages.gift_result(player, ["领到「全服预约礼包100人」×1！去「物品→其他」打开它。"])
	if bus != null:
		bus.item_obtained.emit(StringName("yufu_libao"), 1)


## 改名提交（契约 §5.8）：等级校验在此（PlayerCore.rename 只管名字合法性）
func _rename_submit(nick: String) -> void:
	var card_id := _first_effect_item("rename")
	if card_id == "":
		page = Pages.notice_page("你包里没有改名卡。", "items:other", "返回")
		return
	var eff: Dictionary = GameData.get_item(card_id).get("effect", {})
	var req := maxi(int(eff.get("req_level", 30)), 1)
	if player.level < req:
		input_mode = "rename"
		page = Pages.rename_page(player, "等级不足：要 %d 级才能使用改名卡（当前 %d 级）。" % [req, player.level])
		return
	if not player.rename(nick):
		input_mode = "rename"
		page = Pages.rename_page(player, "名字不能为空，也不能超过 12 个字。")
		return
	player.remove_stack(card_id, 1)
	needs_save = true
	page = Pages.rename_result(player)


## 包内第一个带指定 effect kind 的物品 id（没有则 ""）
func _first_effect_item(kind: String) -> String:
	for id: String in player.bag:
		var eff: Dictionary = GameData.get_item(id).get("effect", {})
		if String(eff.get("kind", "")) == kind and int(player.bag[id]) > 0:
			return id
	return ""
