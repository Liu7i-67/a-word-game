extends SceneTree
## 全量自测：数据校验 + 数值公式 + 玩家状态 + 战斗 + 事件链路 + 存档往返。
## 运行：Godot --headless --path . -s scripts/self_test.gd
## 退出码 0 = 全部通过。

var fails: Array[String] = []
var _started := false


func _initialize() -> void:
	# 测试在首帧执行：保证 add_child 的 UI 节点 _ready 已触发
	pass


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	GameData.load_all()
	_test_data()
	_test_rules()
	var player := PlayerCore.new()
	root.add_child(player)
	player.rng.seed = 20260920
	_test_player(player)
	_test_combat(player)
	_test_router(player)
	_test_title_click_path(player)
	_test_player_roundtrip(player)
	_test_save_manager()
	if fails.is_empty():
		print("SELF_TEST PASS")
	else:
		for f in fails:
			printerr("FAIL: " + f)
		print("SELF_TEST FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)
	return true


func check(cond: bool, what: String) -> void:
	if not cond:
		fails.append(what)


# ---------- 1. 数据完整性 ----------

func _test_data() -> void:
	check(not GameData.config.is_empty(), "config.json 未加载")
	check(Pages.story_pages().size() == 7, "开场剧情应为 7 页")
	var t := Pages.story_title()
	check(String(t.get("name", "")) == "縱橫四海", "标题页名字错误")
	check(not GameData.items.is_empty(), "items.json 未加载")
	check(GameData.monsters.has("bingji"), "缺少怪物：病鸡")
	check(GameData.scenes_by_id.size() == 25, "场景数应为 25，实际 %d" % GameData.scenes_by_id.size())
	check(GameData.ports.size() == 10, "传送港口应为 10 个")

	var npc_kinds := ["flavor", "welfare", "church", "bank", "casino", "market", "teleport", "sail", "dungeon"]
	for id in GameData.scene_order:
		var scene: Dictionary = GameData.scenes_by_id[id]
		check(String(scene.get("name", "")) != "", "场景 %s 缺 name" % id)
		check(String(scene.get("short", "")) != "", "场景 %s 缺 short" % id)
		var seen_dir := {}
		for e: Dictionary in scene.get("exits", []):
			var dir := String(e.get("dir", ""))
			check(dir != "", "场景 %s 出口缺方向" % id)
			if bool(e.get("locked", false)):
				check(String(e.get("name", "")) != "", "场景 %s 锁定出口缺名称" % id)
			else:
				var to := String(e.get("to", ""))
				check(GameData.scenes_by_id.has(to), "场景 %s 出口指向不存在的场景 %s" % [id, to])
			check(not seen_dir.has(dir + str(e.get("to", e.get("name", "")))), "场景 %s 出口重复 %s" % [id, dir])
			seen_dir[dir + str(e.get("to", e.get("name", "")))] = true
		for npc: Dictionary in scene.get("npcs", []):
			check(npc_kinds.has(String(npc.get("kind", ""))), "场景 %s NPC kind 非法" % id)
		for m: Dictionary in scene.get("monsters", []):
			check(GameData.monsters.has(String(m.get("id", ""))), "场景 %s 引用不存在的怪物" % id)

	for mid: String in GameData.monsters:
		var m: Dictionary = GameData.monsters[mid]
		var drop := String(m.get("drop_item", ""))
		check(drop == "" or GameData.items.has(drop), "怪物 %s 掉落物 %s 不存在" % [mid, drop])
		var atk: Array = m.get("atk", [])
		check(atk.size() == 2 and int(atk[1]) >= int(atk[0]), "怪物 %s 攻击区间非法" % mid)
		var exp_r: Array = m.get("exp", [])
		check(exp_r.size() == 2, "怪物 %s 经验区间非法" % mid)

	for iid: String in GameData.items:
		var def: Dictionary = GameData.items[iid]
		check(String(def.get("name", "")) != "", "物品 %s 缺 name" % iid)
		if String(def.get("type", "")) == "equip":
			var atk: Array = def.get("atk", [])
			check(atk.size() == 2 and int(atk[1]) >= int(atk[0]), "装备 %s 攻击区间非法" % iid)


# ---------- 2. 数值公式 ----------

func _test_rules() -> void:
	check(Rules.exp_to_next(1) == 500, "1 级升级经验应为 500（文档✅）")
	check(Rules.exp_to_next(2) == 1000, "2 级升级经验线性")
	check(Rules.max_hp(1) == 100, "1 级体力上限 100")
	check(Rules.base_atk(1) == Vector2i(5, 15), "裸身攻击区间")
	check(Rules.base_def(1) == 0, "1 级防御 0")
	check(Rules.sell_price(26) == 13, "卖价=买价50%")
	check(Rules.retreat_cost(1) == 10, "病鸡撤退费")
	check(Rules.death_loss(0) >= 1, "战败丢失有下限")
	check(Rules.death_loss(1000000) <= 5000, "战败丢失有上限")
	check(Rules.heal_amount() == 50, "教堂治疗+50（文档✅）")
	check(Rules.welfare_copper() == 10000, "福利+10000（文档✅）")
	check(Rules.casino_bet() == 200 and Rules.casino_win() == 1000, "赌场 200/1000（文档✅）")
	check(Rules.teleport_cost_silver() == 10, "传送 10 银（文档✅）")


# ---------- 3. 玩家状态 ----------

func _test_player(player: PlayerCore) -> void:
	player.new_game("测试水手", "♂")
	check(player.level == 1 and player.hp_cur == 100, "新角色基础属性")
	check(player.nickname == "测试水手" and player.gender == "♂", "新角色名字性别")
	check(player.location == "zaugun", "出生点为酒馆")
	check(player.hand == 0 and player.equips.size() == 1, "新角色手持华丽弯刀")
	check(player.atk_range() == Vector2i(14, 37), "带弯刀攻击区间 14-37")
	check(player.weight() == 1, "负重=弯刀1")

	player.add_exp(499)
	check(player.level == 1, "499 经验不升级")
	player.add_exp(1)
	check(player.level == 2 and player.exp_cur == 0, "满 500 升级")
	check(player.max_hp() == 120, "升级体力上限提升")

	player.hurt(200)
	check(player.hp_cur == 0, "伤害归零")
	player.heal(Rules.heal_amount())
	check(player.hp_cur == 50, "治疗 +50")

	player.add_copper(1000)
	check(player.spend_copper(500) and player.copper == 500, "随身扣款")
	check(not player.spend_copper(999999), "余额不足拒绝")
	check(player.bank_deposit(5), "存 5 银")
	check(player.copper == 0 and player.bank_silver == 5, "存后余额")
	check(player.spend_copper(300), "自动从银行折兑")
	check(player.bank_silver == 2 and player.copper == 0, "折兑后 银行2银 随身0")
	player.add_copper(50)
	check(player.spend_copper(100), "随身+银行组合支付")
	check(player.bank_silver == 1 and player.copper == 50, "组合支付后 银行1银 随身50")
	check(player.bank_withdraw(1) and player.copper == 150 and player.bank_silver == 0, "取款")

	player.add_sin(30)
	player.add_sin(-Rules.confess_reduce())
	check(player.sin == 20, "忏悔减罪恶")

	check(player.add_stack("putaojiu", 900), "买入 900 箱葡萄酒")
	check(player.count_stack("putaojiu") == 900, "堆叠数量")
	check(not player.remove_stack("putaojiu", 901), "超量移除拒绝")
	check(player.remove_stack("putaojiu", 100), "移除部分")

	var idx := player.add_equip("xiaojinsiteng")
	check(idx >= 0, "拾取小金丝藤")
	check(player.equip_hand(idx) == "", "换持小金丝藤")
	check(player.atk_range() == Vector2i(11, 30), "2级+小金丝藤攻击区间 11-30")
	check(player.equip_hand(0) == "", "换回弯刀")
	var broke := ""
	for i in 400:
		var result := player.damage_hand()
		if result != "":
			broke = result
	check(broke == "华丽弯刀（1级）", "耐久耗尽武器损坏")
	check(player.hand == -1 and player.atk_range() == Vector2i(7, 20), "损坏后空手回归裸身攻击")


# ---------- 4. 战斗 ----------

func _test_combat(player: PlayerCore) -> void:
	player.new_game("战斗员", "♂")
	player.rng.seed = 42
	var engine := CombatEngine.new("bingji", player)
	check(engine.monster_hp == 40 and engine.monster_def == 8, "病鸡数据（文档✅）")
	var rounds := 0
	var hp_before := player.hp_cur
	while not engine.finished and rounds < 100:
		engine.attack_round(player)
		rounds += 1
	check(engine.finished, "战斗在 100 回合内结束")
	check(engine.won, "满装玩家应战胜病鸡")
	check(engine.monster_hp == 0, "怪物体力归零")
	check(player.hp_cur < hp_before, "玩家受到过伤害")
	check(engine.reward_exp >= 1 and engine.reward_exp <= 9, "经验 1-9（文档✅）")
	check(engine.reward_copper >= 5 and engine.reward_copper <= 30, "掉落铜贝区间")
	check(player.copper == engine.reward_copper, "奖励入账")
	check(player.exp_cur == engine.reward_exp or player.level > 1, "经验入账")
	check(player.equips.any(func(inst: Dictionary) -> bool: return String(inst.get("id", "")) == "xiaojinsiteng") or engine.reward_item == "", "掉落入包")

	var e2 := CombatEngine.new("bingji", player)
	check(e2.retreat_cost() == 10, "撤退费=等级×10")


# ---------- 5. 事件链路 ----------

func _test_router(player: PlayerCore) -> void:
	var router := EventRouter.new()
	var started := [0]
	router.game_started.connect(func() -> void: started[0] += 1)
	router.setup(player, null)

	# 开场 → 建号
	router.handle("story:-1")
	check(router.page.contains("縱橫四海"), "标题页")
	router.handle("story:0")
	check(router.page.contains("金色的沙滩"), "剧情第 1 页")
	router.handle("story:6")
	check(router.page.contains("海盗船长"), "剧情第 7 页")
	router.handle("story:99")
	check(router.input_mode == "char_name", "进入角色创建（需输入）")
	router.handle("create:♂", "")
	check(started[0] == 0, "空名字不应建号")
	router.handle("create:♂", "  马可波罗 ")
	check(started[0] == 1, "建号成功触发 game_started")

	# 场景移动
	router.open_start_scene()
	check(router.page.contains("威尼斯酒馆"), "出生场景渲染")
	check(router.page.contains("老板(新手指引)"), "NPC 链接渲染")
	router.handle("goto:baksingmun")
	check(router.page.contains("北城门") and router.page.contains("矿山（暂未开放）"), "出口渲染（含锁定）")
	router.handle("goto:nowhere")
	check(router.page.contains("走不通"), "非法移动兜底")

	# NPC 对白（逐字文案）
	router.handle("goto:zaugun")
	router.handle("npc:zaugun:boss")
	check(router.page.contains("欢迎来到这个世界"), "酒馆老板对白")
	router.handle("goto:wonggung")
	router.handle("npc:wonggung:king")
	check(router.page.contains("尊敬的马可波罗"), "国王对白昵称替换")

	# 农场战斗闭环
	router.handle("goto:nungcoeng")
	check(router.page.contains("病鸡"), "农场病鸡链接")
	router.handle("fight:bingji")
	check(router.page.contains("敌方属性"), "进入战斗页")
	router.handle("back_game")
	check(router.page.contains("战斗正酣"), "战斗中禁止离开")
	var guarded := 0
	while router.combat != null and not router.combat.finished and guarded < 200:
		router.handle("attack")
		guarded += 1
	check(router.combat != null and router.combat.finished, "战斗结束")
	if router.combat.won:
		check(router.page.contains("战胜了"), "胜利页")
		router.handle("combat_reward")
		check(router.page.contains("经验：+"), "战利品页")
	else:
		check(router.page.contains("狠狠教训"), "战败页（好心人救回）")
		check(player.location == Rules.revive_scene(), "战败送回城里")
	router.handle("combat_leave")
	check(router.combat == null, "战斗状态清理")
	var here: String = GameData.get_scene(player.location).get("name", "")
	check(router.page.contains(here), "回到场景页")

	# 教堂
	var hp0 := player.hp_cur
	router.handle("goto:gaautong")
	router.handle("npc:gaautong:priest")
	check(router.page.contains("免费为你提供治疗"), "神父对白")
	router.handle("heal")
	check(player.hp_cur == mini(hp0 + 50, player.max_hp()), "治疗 +50")
	router.handle("confess")
	check(router.page.contains("罪恶值"), "忏悔页")

	# 福利（每周一次）
	router.handle("goto:fukleijyun")
	router.handle("npc:fukleijyun:officer")
	var copper0 := player.copper
	router.handle("welfare_claim")
	check(player.copper == copper0 + 10000, "领福利 +10000")
	check(not player.welfare_claimable(), "本周不可重复领取")
	router.handle("welfare_claim")
	check(player.copper == copper0 + 10000, "重复领取无效")

	# 银行
	router.handle("goto:nganhong")
	router.handle("npc:nganhong:clerk")
	check(router.page.contains("最安全的现金保管"), "银行职员对白")
	player.add_copper(3000)
	router.handle("deposit:10")
	check(player.bank_silver >= 10, "存 10 银")
	router.handle("withdraw:all")
	check(player.bank_silver == 0, "取出全部")

	# 赌场
	router.handle("goto:doucoeng")
	router.handle("npc:doucoeng:croupier")
	check(router.page.contains("服务费10%"), "博彩MM对白")
	player.add_copper(10000)
	var c0 := player.copper
	router.handle("dice_page")
	router.handle("dice:big")
	check(router.page.contains("骰子："), "赌大小出结果")
	check(player.copper == c0 - 200 or player.copper == c0 + 800, "赌大小输 200 / 赢 1000")
	router.handle("rps_page")
	router.handle("rps:rock")
	check(router.page.contains("你出了"), "猜拳出结果")
	router.handle("again")
	check(router.page.contains("服务费10%"), "再来一次回赌场主页面")

	# 市场
	router.handle("goto:sicoeng")
	router.handle("npc:sicoeng:vendor")
	check(router.page.contains("本地特产"), "供应商对白")
	check(router.page.contains("26铜贝/箱"), "葡萄酒价格（文档✅）")
	player.add_copper(50000)
	var g0 := player.count_stack("putaojiu")
	router.handle("buy:putaojiu:225")
	check(player.count_stack("putaojiu") == g0 + 225, "买入 225 箱")
	var cu0 := player.copper
	var g1 := player.count_stack("putaojiu")
	router.handle("sell:putaojiu:all")
	check(player.count_stack("putaojiu") == 0, "全部卖出")
	check(player.copper == cu0 + g1 * 13, "卖价 13 铜贝/箱")

	# 物品 / 装备
	router.handle("items:equip")
	check(router.page.contains("华丽弯刀"), "物品页装备列表")
	var eq_count := player.equips.size()
	if eq_count > 0:
		router.handle("equip_view:0")
		check(router.page.contains("耐久"), "装备详情页")
	router.handle("equip_off:0" if player.hand == 0 else "equip_view:0")

	# 状态 / 地图 / 传送
	router.handle("status")
	check(router.page.contains("昵称：马可波罗"), "状态页")
	router.handle("map")
	check(router.page.contains("威尼斯城内地图"), "城内地图")
	router.handle("goto:maatau")
	router.handle("npc:maatau:teleporter")
	check(router.page.contains("地中海"), "传送页")
	router.handle("tp:1")
	check(router.page.contains("暂未开发区域"), "未开放港口占位（原文案）")
	router.handle("npc:maatau:sailor")
	check(router.page.contains("暂未开发区域"), "出航占位（原文案）")
	router.handle("goto:baksingmun")
	router.handle("npc:baksingmun:explorer")
	check(router.page.contains("威尼斯地宫"), "探险官对白")
	router.handle("dungeon_try")
	check(router.page.contains("暂未开发区域"), "地宫占位")


# ---------- 5.5 标题屏真实点击路径（回归：创建页必须有可见输入框） ----------

func _test_title_click_path(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	var ts := TitleScreen.new(router)
	root.add_child(ts)
	for event in ["story:0", "story:1", "story:2", "story:3", "story:4", "story:5", "story:6", "story:99"]:
		ts._on_link(event)
	check(router.input_mode == "char_name", "点击路径：story:99 进入输入模式")
	check(ts._input_row.visible, "点击路径：创建页输入框可见")
	check(ts._input_row.get_index() == 0, "输入框位于页面区上方（防窗口过矮/键盘遮挡）")
	check(ts._name_edit.editable, "输入框可编辑")
	ts.queue_free()


# ---------- 6. 存档往返 ----------

func _test_player_roundtrip(player: PlayerCore) -> void:
	player.new_game("存档员", "♀")
	player.add_copper(888)
	player.add_stack("putaojiu", 300)
	player.bank_deposit(2)
	var save := {}
	player.write_to(save)
	var clone := PlayerCore.new()
	root.add_child(clone)
	check(clone.read_from(save), "read_from 成功")
	check(clone.nickname == "存档员" and clone.gender == "♀", "往返：名字性别")
	check(clone.copper == 688 and clone.bank_silver == 2, "往返：货币（888-200存银）")
	check(clone.count_stack("putaojiu") == 300, "往返：背包")
	check(clone.hand == 0 and clone.equips.size() == 1, "往返：装备")
	check(clone.location == "zaugun", "往返：位置")
	var bad := clone.read_from({})
	check(not bad, "空存档拒绝")


func _test_save_manager() -> void:
	var save_script: GDScript = load("res://scripts/autoload/save_manager.gd")
	var writer: Node = save_script.new()
	root.add_child(writer)
	writer.data["gold"] = 123
	writer.save_game()

	var reader: Node = save_script.new()
	root.add_child(reader)
	reader.load_game()

	var gold: Variant = reader.data.get("gold", "MISSING")
	var version: Variant = reader.data.get("_version", "MISSING")
	check(gold == 123 and version == 1, "SaveManager 往返 gold/version")
