extends RefCounted
## 开发用页面走查：驱动路由遍历各页面并截图。
## 运行：Godot --path . --audio-driver Dummy -- --shot-tour
## 输出目录：环境变量 SHOT_DIR（默认 user://shots）。

var _dir := ""
var _main: Control
var _logs: PackedStringArray = []


func _log(msg: String) -> void:
	_logs.append(msg)
	var file := FileAccess.open(OS.get_user_data_dir() + "/tour_debug.log", FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_logs))
		file.close()
	print(msg)


func run(main: Control) -> void:
	_log("TOUR: run() 开始")
	_main = main
	if OS.get_cmdline_user_args().has("--create-repro"):
		await _create_repro(main)
		return
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(_dir)
	var router: EventRouter = main.router
	await _wait(8)
	_log("TOUR: 首帧等待完成")

	# 标题 / 剧情 / 建号
	var title: Control = main.title_screen
	await _shot("01_title")
	_drive(title, "story:0")
	await _shot("02_story_1")
	_drive(title, "story:7")
	await _shot("03_story_last")
	_drive(title, "story:99")
	title._input_row.visible = true
	title._name_edit.text = "马可波罗"
	await _shot("04_create")

	# 模拟异形屏走查：user args 带 --sim-insets=左,上,右,下 时补拍 35/36，
	# 用代码注入模拟 insets（免重启进程）；无该参数则跳过
	var sim_insets := SafeAreaFrame.parse_sim_insets(OS.get_cmdline_user_args())
	var sim_active := sim_insets.x >= 0.0
	if sim_active:
		title._safe_frame.set_simulated_insets(sim_insets)
		await _shot("35_insets_title")
		title._safe_frame.set_simulated_insets(SafeAreaFrame.NO_INSETS)

	# 建号 → 游戏屏
	_drive(title, "create:♂")
	await _wait(10)
	var game: Control = main.game_screen
	if game == null:
		printerr("SHOT TOUR: game_screen 未创建")
		main.get_tree().quit(1)
		return

	await _shot("05_scene_inn")
	_play(game, "status")
	await _shot("06_status")
	_play(game, "items:equip")
	await _shot("07_items_equip")
	_play(game, "equip_view:0")
	await _shot("08_equip_detail")
	_play(game, "map")
	await _shot("09_city_map")
	_play(game, "back_game")

	# 战斗闭环
	_play(game, "goto:nungcoeng")
	await _shot("10_farm")
	_play(game, "fight:bingji")
	await _shot("11_combat")
	_play(game, "attack")
	_play(game, "attack")
	await _shot("12_combat_rounds")
	for i in 30:
		if router.combat != null and not router.combat.finished:
			_play(game, "attack")
	await _shot("13_combat_end")
	_play(game, "combat_reward")
	await _shot("14_reward")
	_play(game, "combat_leave")

	# 教堂 / 福利
	_play(game, "goto:gaautong")
	_play(game, "npc:gaautong:priest")
	await _shot("15_church")
	_play(game, "heal")
	await _shot("16_heal")
	_play(game, "goto:fukleijyun")
	_play(game, "npc:fukleijyun:officer")
	_play(game, "welfare_claim")
	await _shot("17_welfare")

	# 银行
	_play(game, "goto:nganhong")
	_play(game, "npc:nganhong:clerk")
	await _shot("18_bank")
	_play(game, "bank_deposit")
	await _shot("19_bank_deposit")
	_play(game, "deposit:all")

	# 赌场
	_play(game, "goto:doucoeng")
	_play(game, "npc:doucoeng:croupier")
	await _shot("20_casino")
	_play(game, "dice_page")
	_play(game, "dice:big")
	await _shot("21_dice")
	_play(game, "rps_page")
	_play(game, "rps:rock")
	await _shot("22_rps")

	# 市场
	_play(game, "goto:sicoeng")
	_play(game, "npc:sicoeng:vendor")
	await _shot("23_market")
	_play(game, "buy:putaojiu:225")
	await _shot("24_market_buy")
	_play(game, "sell_page")
	await _shot("25_market_sell")

	# 码头 / 传送 / 探险官
	_play(game, "goto:maatau")
	_play(game, "npc:maatau:teleporter")
	await _shot("26_teleport")
	_play(game, "goto:baksingmun")
	_play(game, "npc:baksingmun:explorer")
	await _shot("27_explorer")
	_play(game, "npc:baksingmun:guard")
	await _shot("28_guard")

	# 扩展走查：商店 / 铁匠 / 地宫 / 战斗用药（测试号先补等级、铜贝与打造材料）
	router.player.add_exp(5000)
	router.player.add_copper(30000)
	router.player.add_stack("niupi", 8)
	_play(game, "goto:soengdim")
	_play(game, "npc:soengdim:merchant")
	await _shot("29_shop")
	_play(game, "buy_drug:pingguo:10")
	await _shot("30_shop_buy")
	_play(game, "goto:titzoengpou")
	_play(game, "npc:titzoengpou:smith")
	await _shot("31_smith")
	_play(game, "forge_page")
	await _shot("32_forge")
	_play(game, "forge:niupibian")
	_play(game, "goto:baksingmun")
	_play(game, "npc:baksingmun:explorer")
	_play(game, "dungeon_try")
	await _shot("33_dungeon")
	_play(game, "fight:qiang_jie_zhe")
	router.player.hurt(150)
	_play(game, "combat_drug")
	await _shot("34_combat_drug")
	_play(game, "combat_back")
	_play(game, "retreat")

	# 游戏场景页的模拟异形屏走查（与 35 同参数）
	if sim_active:
		game._safe_frame.set_simulated_insets(sim_insets)
		await _shot("36_insets_game")
		game._safe_frame.set_simulated_insets(SafeAreaFrame.NO_INSETS)

	# 航海贸易走查（契约 docs/trade-spec.md §9）：world 数据就位时补拍
	# 37 港口市场页（含🔥抢手）/ 38 酒保情报页 / 39 传送页；缺失则跳过（联调补拍）
	if GameData.world_ports.size() >= 2 and GameData.has_scene(String(GameData.world_ports[1].get("scene", ""))):
		router.player.add_copper(500000)
		var pscene := String(GameData.world_ports[1].get("scene", ""))
		_play(game, "tp:1")
		_play(game, "npc:%s:merchant" % pscene)
		await _shot("37_trade_market")
		_play(game, "npc:%s:barkeep" % pscene)
		_play(game, "rumor")
		await _shot("38_rumor")
		_play(game, "npc:%s:teleporter" % pscene)
		await _shot("39_teleport")
	else:
		_log("TOUR SKIP: world 数据未就位，跳过 37-39 航海贸易截图")
	# 40 装备回收页（铁匠，任何数据状态都可拍）；补三把大环刀并成交一把，
	# 让截图同时呈现「全部出售批量入口」与「卖出后留在本页」的成交提示
	_play(game, "goto:titzoengpou")
	_play(game, "npc:titzoengpou:smith")
	for i in 3:
		router.player.add_equip("dahuandao")
	var dup_idx := -1
	for i in router.player.equips.size():
		if String(router.player.equips[i].get("id", "")) == "dahuandao":
			dup_idx = i
			break
	_play(game, "sell_equip_page")
	if dup_idx >= 0:
		_play(game, "sell_equip:%d" % dup_idx)
	await _shot("40_sell_equip")

	# 走查 41+：生活系统 / 酒馆新 NPC / 大世界 / 强化宝石（契约 plan-v2 §6）
	_play(game, "goto:zaugun")
	_play(game, "npc:zaugun:boss")
	await _shot("41_tavern_boss")
	_play(game, "npc:zaugun:deluoxi")
	await _shot("42_circus")
	_play(game, "npc:zaugun:andedalu")
	await _shot("43_trainer")
	_play(game, "npc:zaugun:xiliya")
	await _shot("44_siren")
	_play(game, "npc:zaugun:aobupasi")
	await _shot("45_riddle")
	_play(game, "goto:soenmon")
	_play(game, "npc:soenmon:zhushou")
	await _shot("46_alchemy")

	# 打坐：补野球草人与等级，任意无怪场景出「打坐」入口
	router.player.add_stack("yeqiu_caoren", 1)
	router.player.add_exp(25000)
	router.player.add_copper(200000)
	router.player.stamina = router.player.max_stamina()
	_play(game, "goto:zaugun")
	_play(game, "meditate")
	await _shot("47_meditate")

	# 钓鱼（用活饵）
	router.player.add_stack("xiaoyu_huoer", 5)
	router.player.stamina = router.player.max_stamina()
	_play(game, "goto:haitan")
	_play(game, "fish:bait")
	await _shot("48_fishing")

	# 种田：播种第一块地
	router.player.add_stack("mucao_zhongzi", 4)
	router.player.stamina = router.player.max_stamina()
	_play(game, "goto:nungcoeng")
	_play(game, "farm")
	_play(game, "farm_plant:0")
	await _shot("49_farm")

	# 潜水（临时把潜水表定死为珍珠，避免随机起战斗干扰截图；拍完还原）
	var dive_cfg: Dictionary = GameData.config.get("life", {})
	var saved_dive: Array = (dive_cfg.get("dive_table", []) as Array).duplicate()
	dive_cfg["dive_table"] = [{"id": "zhenzhu", "w": 100}]
	router.player.stamina = router.player.max_stamina()
	_play(game, "goto:tsienhoi")
	_play(game, "dive")
	await _shot("50_dive")
	dive_cfg["dive_table"] = saved_dive

	# 大世界地图（只读展示页）
	_play(game, "worldmap")
	await _shot("51_worldmap")

	# 铁匠强化 + 宝石镶嵌（补龙泉水/宝石/带插槽护甲）
	router.player.add_stack("longquanshui", 9)
	router.player.add_stack("lanbaoshi", 2)
	router.player.add_equip("cuzhitongkui")
	_play(game, "goto:titzoengpou")
	_play(game, "npc:titzoengpou:smith")
	_play(game, "smith_enhance")
	await _shot("52_enhance")
	var gem_target := -1
	for i in router.player.equips.size():
		if int(GameData.get_item(String(router.player.equips[i].get("id", ""))).get("slots", 0)) > 0:
			gem_target = i
			break
	_play(game, "smith_gem")
	if gem_target >= 0:
		_play(game, "smith_gem:%d" % gem_target)
	await _shot("53_gem")

	print("SHOT TOUR DONE -> ", _dir)
	main.get_tree().quit(0)


## 复现真实点击路径：逐页走 TitleScreen._on_link，观察输入框状态
func _create_repro(main: Control) -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(_dir)
	var title: Control = main.title_screen
	await _wait(8)
	var events := ["story:0", "story:1", "story:2", "story:3", "story:4", "story:5", "story:6", "story:99"]
	for i in events.size():
		title._on_link(events[i])
		_log("REPRO after %s -> input_mode=%s row_visible=%s" % [
			events[i], main.router.input_mode, title._input_row.visible])
	title._view.visible_ratio = 1.0
	await _wait(4)
	await RenderingServer.frame_post_draw
	var img: Image = main.get_viewport().get_texture().get_image()
	img.save_png(_dir + "/repro_create.png")
	_log("REPRO saved, row_visible=%s row_size=%s row_global=%s" % [
		title._input_row.visible, title._input_row.size, title._input_row.global_position])
	main.get_tree().quit(0)


## 标题屏页面驱动（绕开点击冷却，直接走 router + 渲染）
func _drive(title: Control, event: String) -> void:
	var router: EventRouter = _main.router
	if event.begins_with("create:"):
		router.handle(event, title._name_edit.text)
	else:
		router.handle(event)
	title._input_row.visible = router.input_mode == "char_name"
	title._render()
	title._view.visible_ratio = 1.0


## 游戏屏页面驱动（router + 存档 + 顶栏刷新，与 _on_link 同管线但无冷却）
func _play(game: Control, event: String) -> void:
	var router: EventRouter = _main.router
	router.handle(event)
	game._after_event()
	game._view.visible_ratio = 1.0


func _shot(name: String) -> void:
	_log("TOUR: 截图排队 " + name)
	await _wait(4)
	await RenderingServer.frame_post_draw
	var img: Image = _main.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	img.save_png(path)
	_log("TOUR: 已保存 " + path)


func _wait(frames: int) -> void:
	for i in frames:
		await _main.get_tree().process_frame
