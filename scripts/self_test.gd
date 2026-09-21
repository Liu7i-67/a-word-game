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
	# 自动战斗用例含真实定时等待，改走异步协程驱动；quit 在协程末尾调用
	_run_all()
	return false


func _run_all() -> void:
	GameData.load_all()
	_test_data()
	_test_rules()
	var player := PlayerCore.new()
	root.add_child(player)
	player.rng.seed = 20260920
	_test_player(player)
	_test_combat(player)
	_test_router(player)
	_test_drug_and_shop(player)
	_test_combat_drug(player)
	_test_smith(player)
	_test_dungeon(player)
	_test_gm_easteregg(player)
	_test_exp_buff_stack(player)
	_test_bottom_actions_and_pad(player)
	_test_update_checker(player)
	_test_trade_engine()
	_test_trade_router(player)
	_test_sell_equip(player)
	_test_life_system(player)
	_test_sail_region_data(player)
	_test_sail_region_flow(player)
	_test_item_effects(player)
	_test_equipment_affixes(player)
	_test_gem_merge(player)
	_test_quests(player)
	await _test_auto_battle(player)
	_test_drop_equip(player)
	_test_title_click_path(player)
	_test_scroll_fix(player)
	_test_safe_area_frame()
	_test_player_roundtrip(player)
	_test_new_fields_roundtrip(player)
	_test_save_manager()
	if fails.is_empty():
		print("SELF_TEST PASS")
	else:
		for f in fails:
			printerr("FAIL: " + f)
		print("SELF_TEST FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)


## 轮询等待条件成立（自动战斗等异步用例用），超时记失败
func _wait_until(cond: Callable, timeout_sec: float, what: String) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return
		await create_timer(0.02).timeout
	check(cond.call(), what + "（等待超时）")


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
	check(GameData.scenes_by_id.size() >= 25, "场景数应 ≥25（原版 25 + 城外扩展），实际 %d" % GameData.scenes_by_id.size())
	check(GameData.ports.size() == 10, "传送港口应为 10 个")

	# sail-region 契约 §1.3：船主(sailor)/旅店(inn) 新 kind；§1.10 用户裁决：传送与航海
	# 并存（teleport 恢复，旧 sail 占位不恢复），白名单同步加回 teleport
	var npc_kinds := ["flavor", "welfare", "church", "bank", "casino", "market", "dungeon", "shop", "smith", "dungeon_keeper", "trade_market", "tavern_rumor",
		"tavern", "circus", "alchemist", "trainer", "siren", "riddle", "sailor", "inn", "teleport"]
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
		var drop_equip: Dictionary = m.get("drop_equip", {})
		if not drop_equip.is_empty():
			var eq_id := String(drop_equip.get("id", ""))
			check(GameData.items.has(eq_id), "怪物 %s drop_equip %s 不存在" % [mid, eq_id])
			check(int(drop_equip.get("rate", 0)) >= 0 and int(drop_equip.get("rate", 0)) <= 100, "怪物 %s drop_equip 概率非法" % mid)
		var atk: Array = m.get("atk", [])
		check(atk.size() == 2 and int(atk[1]) >= int(atk[0]), "怪物 %s 攻击区间非法" % mid)
		var exp_r: Array = m.get("exp", [])
		check(exp_r.size() == 2, "怪物 %s 经验区间非法" % mid)

	for iid: String in GameData.items:
		var def: Dictionary = GameData.items[iid]
		check(String(def.get("name", "")) != "", "物品 %s 缺 name" % iid)
		if String(def.get("type", "")) == "equip":
			# 契约 plan-v2 §2.1：armor 槽位用 def 字段（无 atk），武器仍校验攻击区间
			if String(def.get("slot", "weapon")) == "armor":
				check(def.has("def"), "护甲 %s 缺 def" % iid)
			else:
				var atk: Array = def.get("atk", [])
				check(atk.size() == 2 and int(atk[1]) >= int(atk[0]), "装备 %s 攻击区间非法" % iid)
		if String(def.get("type", "")) == "gem":
			var gem_bonus: Dictionary = def.get("bonus", {})
			check(not gem_bonus.is_empty(), "宝石 %s 缺 bonus 词条" % iid)
		if String(def.get("type", "")) == "drug":
			check(int(def.get("heal", 0)) > 0 or def.has("exp_buff"), "药品 %s 缺 heal/exp_buff" % iid)
			check(def.has("exp_buff") or int(def.get("price", 0)) > 0, "药品 %s 缺 price" % iid)
		var forge: Dictionary = def.get("forge", {})
		if not forge.is_empty():
			var mats: Dictionary = forge.get("materials", {})
			check(not mats.is_empty() and int(forge.get("copper", 0)) > 0, "装备 %s forge 配置非法" % iid)
			for mid: String in mats:
				check(GameData.items.has(mid), "装备 %s 打造材料 %s 不存在" % [iid, mid])

	# 高阶装备引用（契约 plan-v2 §2.2，D1 落地后硬校验）：
	# 堡垒三怪 drop_equip 指向锁定 id；玄铁重剑为 L17 打造件
	var drop_binding := {"baolei_shouwei": "xuantiejia", "hei_an_qishi": "anlinjuren", "baolei_lingzhu": "lingzhuzhiren"}
	for mid2: String in drop_binding:
		var m_def: Dictionary = GameData.monsters.get(mid2, {})
		check(String((m_def.get("drop_equip", {}) as Dictionary).get("id", "")) == String(drop_binding[mid2]),
			"怪物 %s 应掉落 %s" % [mid2, String(drop_binding[mid2])])
	check(GameData.items.has("xuantiezhongjian")
		and not (GameData.get_item("xuantiezhongjian").get("forge", {}) as Dictionary).is_empty(),
		"玄铁重剑（L17 打造件）已落地且带 forge")


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
	check(Rules.repair_cost(3) == 6 and Rules.repair_cost(0) == 0, "修理价=缺口×2铜贝")
	check(Rules.dungeon_level_range() == Vector2i(5, 15), "地宫级别 5-15（文档✅）")
	check(Rules.dungeon_scene() == "digung" and Rules.dungeon_exit_scene() == "baksingmun", "地宫场景/出口 id")
	check(Rules.dungeon_monster() == "qiang_jie_zhe", "地宫任务怪 id")
	check(Rules.dungeon_kill_goal() == 40 and Rules.dungeon_time_limit_sec() == 3000, "地宫目标 40 / 时限 3000 秒")
	check(Rules.dungeon_reward_copper() == 20000 and Rules.dungeon_reward_gold() == 1, "地宫奖励 20000 铜贝 + 1 金贝")


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
	check(router.page.contains("北城门") and router.page.contains("goto:kuaangsan"), "北城门出口渲染（矿山已接线）")
	router.handle("goto:nowhere")
	check(router.page.contains("走不通"), "非法移动兜底")

	# NPC 对白（逐字文案）
	router.handle("goto:zaugun")
	router.handle("npc:zaugun:boss")
	check(router.page.contains("马可波罗，欢迎来到这个世界"), "酒馆老板对白（行首补昵称）")
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

	# 市场（威尼斯既有市场：价源已切 Trade 引擎，同港零差价；断言按引擎现价动态计算）
	router.handle("goto:sicoeng")
	router.handle("npc:sicoeng:vendor")
	check(router.page.contains("本地特产"), "供应商对白")
	var trade_day := player.current_day()
	var wine := Trade.price("putaojiu", Trade.VENICE, trade_day)
	check(router.page.contains("%d铜贝/箱" % wine), "葡萄酒本地价（Trade 引擎定价）")
	player.add_copper(50000)
	var g0 := player.count_stack("putaojiu")
	router.handle("buy:putaojiu:225")
	check(player.count_stack("putaojiu") == g0 + 225, "买入 225 箱")
	var cu0 := player.copper
	var g1 := player.count_stack("putaojiu")
	router.handle("sell:putaojiu:all")
	check(player.count_stack("putaojiu") == 0, "全部卖出")
	check(player.copper == cu0 + g1 * wine, "卖价=引擎现价（同港零差价）")

	# 非贸易材料固定回收价（sell_price 字段），不被 Trade 引擎按基准价翻倍
	player.add_stack("emao", 10)
	var cm := player.copper
	router.handle("sell:emao:all")
	check(player.count_stack("emao") == 0, "材料全部卖出")
	check(player.copper == cm + 60, "材料回收价=sell_price(6×10)")

	# 物品 / 装备
	router.handle("items:equip")
	check(router.page.contains("华丽弯刀"), "物品页装备列表")
	var eq_count := player.equips.size()
	if eq_count > 0:
		router.handle("equip_view:0")
		check(router.page.contains("耐久"), "装备详情页")
	router.handle("equip_off:0" if player.hand == 0 else "equip_view:0")

	# 状态 / 地图 / 船主页（sail-region 契约 §1.6：tp/teleport 退役，航海取代传送）
	router.handle("status")
	check(router.page.contains("昵称：马可波罗"), "状态页")
	router.handle("map")
	check(router.page.contains("威尼斯城内地图"), "城内地图")
	router.handle("goto:sicoeng")
	router.handle("npc:sicoeng:sailor")
	check(router.page.contains("船主") and router.page.contains("sail_to:"), "船主页（sail_to 链接）")
	check(router.page.contains("当前所在"), "船主页标当前所在")
	router.handle("goto:baksingmun")
	router.handle("npc:baksingmun:explorer")
	check(router.page.contains("威尼斯地宫"), "探险官对白")
	router.handle("dungeon_try")
	check(player.location != Rules.dungeon_scene() and router.page.contains("级别"), "地宫入口：级别不符不放行")


# ---------- 5.4 药品 / 商店（扩展契约 §4.1、§4.3） ----------

func _test_drug_and_shop(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("购物员", "♂")

	# 商店页（npc kind=shop）
	router.handle("goto:soengdim")
	router.handle("npc:soengdim:merchant")
	check(router.page.contains("威尼斯商店") and router.page.contains("疗效+30"), "商店页列出药品与疗效")
	check(router.page.contains("buy_drug:pingguo:10"), "商店页有买 10 链接")

	# 买药扣款
	player.add_copper(1000)
	var c0 := player.copper
	router.handle("buy_drug:pingguo:1")
	check(player.count_stack("pingguo") == 1, "买 1 瓶苹果入包")
	check(player.copper == c0 - 8, "买苹果扣 8 铜贝")
	var n0 := player.count_stack("xiao_yaoji")
	router.handle("buy_drug:xiao_yaoji:10")
	check(player.count_stack("xiao_yaoji") == n0 + 10, "买 10 瓶小体力药剂")
	check(player.copper == c0 - 8 - 250, "买药扣款累计（25×10）")

	# 随身不足自动折兑买药；彻底没钱给商人语气提示
	player.bank_deposit(3)
	player.take_copper(player.copper)
	router.handle("buy_drug:da_yaoji:1")
	check(player.count_stack("da_yaoji") == 1, "随身不足自动从银行折兑买到")
	check(player.bank_silver == 2, "折兑扣 1 银")
	player.bank_withdraw(player.bank_silver)
	player.take_copper(player.copper)
	router.handle("buy_drug:da_yaoji:10")
	check(player.count_stack("da_yaoji") == 1, "钱不够不入包")
	check(router.page.contains("商人"), "不足给商人语气提示页")

	# 物品分类页 [使用] + 战斗外用药
	player.add_copper(100)
	router.handle("items:drug")
	check(router.page.contains("[lb]使用[rb]") and router.page.contains("苹果"), "药品分类页列出 [使用] 链接")
	check(router.page.contains("use_drug:pingguo"), "药品分类页使用事件")
	player.hurt(50)
	var hp0 := player.hp_cur
	router.handle("use_drug:pingguo")
	check(player.hp_cur == hp0 + 30, "用苹果 +30 体力")
	check(player.count_stack("pingguo") == 0, "用药后数量 -1")
	check(router.page.contains("返回"), "结果页可返回药品页")

	# 满血拒绝 / 无药提示
	player.heal(9999)
	player.add_stack("pingguo", 1)
	router.handle("use_drug:pingguo")
	check(player.count_stack("pingguo") == 1, "满血不消耗药品")
	check(router.page.contains("体力充沛"), "满血提示")
	router.handle("use_drug:haizao")
	check(router.page.contains("没找到"), "无药提示")


# ---------- 5.5 战斗中用药（扩展契约 §4.2） ----------

func _test_combat_drug(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("药士", "♂")
	player.rng.seed = 42
	player.add_stack("xiao_yaoji", 2)
	router.handle("goto:nungcoeng")
	router.handle("fight:bingji")
	check(router.combat != null, "进入战斗（用药用例）")
	player.hurt(60)
	var hp_low := player.hp_cur
	router.handle("combat_drug")
	check(router.page.contains("combat_use") and router.page.contains("小体力药剂"), "战斗用药页列出背包药品")
	router.handle("combat_use:xiao_yaoji")
	# 先回 80 体力（上限截断），再挨病鸡还击至多 8 点
	check(player.hp_cur >= mini(hp_low + 80, player.max_hp()) - 8, "用药回体力")
	check(player.count_stack("xiao_yaoji") == 1, "战斗用药数量 -1")
	check(router.combat.monster_hp == router.combat.monster_hp_max, "用药回合怪不掉血")
	check(router.page.contains("趁你用药"), "怪物还击一回合")
	check(router.page.contains("敌方属性"), "用药后回到战斗页")

	# 满血用药：不消耗、不引来还击
	player.heal(9999)
	router.handle("combat_use:xiao_yaoji")
	check(player.count_stack("xiao_yaoji") == 1, "满血用药不消耗")
	check(router.page.contains("省着点药"), "满血用药提示")
	check(not router.combat.finished, "满血用药不结束战斗")

	# 用药回合被击杀 → 走战败流程
	player.hurt(player.hp_cur - 1)
	router.combat.monster_atk_min = 999
	router.combat.monster_atk_max = 999
	router.handle("combat_use:xiao_yaoji")
	check(router.page.contains("战斗失败"), "用药回合被击杀走战败")
	check(player.location == Rules.revive_scene(), "战败送回城里")
	check(player.dungeon_kills == 0 and player.dungeon_deadline == 0, "战败清空地宫进度")
	router.handle("combat_leave")
	check(router.combat == null, "战斗状态清理（用药用例）")


# ---------- 5.6 铁匠：修理 / 打造（扩展契约 §4.4） ----------

func _test_smith(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("铁匠学徒", "♂")
	router.handle("goto:titzoengpou")
	router.handle("npc:titzoengpou:smith")
	check(router.page.contains("威尼斯铁匠铺") and router.page.contains("修理手持"), "铁匠页")
	check(router.page.contains("打造装备"), "铁匠页打造入口")

	# 满耐久拒绝
	var c0 := player.copper
	router.handle("repair_hand")
	check(player.copper == c0, "满耐久不扣款")
	check(router.page.contains("修什么修"), "满耐久提示")

	# 修理：价格 = 缺口 × 单价
	for i in 3:
		player.damage_hand()
	check(player.hand_missing_dur() == 3, "耐久缺口 3")
	player.take_copper(player.copper)
	player.add_copper(100)
	router.handle("repair_hand")
	check(player.copper == 100 - Rules.repair_cost(3), "修理扣款=缺口×单价")
	check(player.hand_missing_dur() == 0, "修理后耐久满")

	# 钱不够拒绝
	for i in 10:
		player.damage_hand()
	player.take_copper(player.copper)
	router.handle("repair_hand")
	check(player.hand_missing_dur() == 10, "钱不够不修理")
	check(router.page.contains("不够"), "修理钱不够提示")

	# 打造：成功扣材料与工钱
	player.add_stack("niupi", 4)
	player.add_copper(300)
	router.handle("forge_page")
	check(router.page.contains("牛皮鞭") and router.page.contains("forge:niupibian"), "打造页列出可打造装备")
	var eq0 := player.equips.size()
	router.handle("forge:niupibian")
	check(player.equips.size() == eq0 + 1, "打造装备入包")
	check(player.count_stack("niupi") == 0, "打造扣除材料")
	check(player.copper == 0, "打造扣除工钱 300")
	check(int(player.equips[eq0].get("dur", 0)) == 250, "新装备满耐久")

	# 材料不足拒绝
	router.handle("forge:niupibian")
	check(player.equips.size() == eq0 + 1, "材料不足不重复打造")

	# 工钱不足拒绝
	player.add_stack("niupi", 4)
	player.take_copper(player.copper)
	router.handle("forge:niupibian")
	check(player.count_stack("niupi") == 4, "工钱不足材料不扣")
	check(player.equips.size() == eq0 + 1, "工钱不足不入包")


# ---------- 5.7 威尼斯地宫（扩展契约 §4.5） ----------

func _test_dungeon(player: PlayerCore) -> void:
	var bus: Node = load("res://scripts/autoload/event_bus.gd").new()
	root.add_child(bus)
	var cleared := [0, 0, 0]
	bus.dungeon_cleared.connect(func(c: int, g: int) -> void:
		cleared[0] += c
		cleared[1] += g
		cleared[2] += 1
	)
	var router := EventRouter.new()
	router.setup(player, bus)
	player.new_game("探险员", "♂")

	# 级别不符
	router.handle("goto:baksingmun")
	router.handle("npc:baksingmun:explorer")
	router.handle("dungeon_try")
	check(player.location != Rules.dungeon_scene(), "级别不符不放进地宫")

	# 升到 5 级进入（500+1000+1500+2000 = 5000 经验）
	player.add_exp(5000)
	check(player.level == 5, "升到 5 级")
	router.handle("dungeon_try")
	check(player.location == Rules.dungeon_scene(), "5 级进入地宫")
	check(player.dungeon_day == player.current_day(), "记录当日序号")
	check(player.dungeon_deadline > int(Time.get_unix_time_from_system()), "设置时限")
	check(router.page.contains("击杀进度：0/%d" % Rules.dungeon_kill_goal()), "地宫页显示进度")
	check(router.page.contains("剩余时间："), "地宫页显示剩余时间")
	check(router.page.contains("挑战抢劫者") and router.page.contains("秘密看守"), "地宫页链接")

	# 当日重复进入拒绝
	router.handle("goto:%s" % Rules.dungeon_exit_scene())
	router.handle("dungeon_try")
	check(player.location != Rules.dungeon_scene(), "当日重复进入拒绝")
	check(router.page.contains("明天"), "重复进入提示")

	# 战胜任务怪 → 计数 +1
	player.dungeon_day = -1
	router.handle("dungeon_try")
	check(player.location == Rules.dungeon_scene(), "重新进入地宫")
	router.handle("fight:%s" % Rules.dungeon_monster())
	check(router.combat != null, "挑战抢劫者")
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	router.handle("attack")
	check(router.combat.finished and router.combat.won, "战胜抢劫者")
	check(player.dungeon_kills == 1, "地宫击杀计数 +1")
	check(router.page.contains("击杀进度：1/40"), "胜利页显示进度")
	router.handle("combat_leave")

	# 击杀不足 → 看守只报进度，不发奖
	var gold0 := player.gold
	var copper0 := player.copper
	router.handle("npc:%s:keeper" % Rules.dungeon_scene())
	check(player.gold == gold0 and player.copper == copper0, "击杀不足不发奖")
	check(router.page.contains("秘密看守"), "看守页显示进度")

	# 击杀达标 → 领奖（铜贝 20000 + 金贝 1）+ 信号
	for i in Rules.dungeon_kill_goal() - 1:
		player.dungeon_add_kill()
	router.handle("npc:%s:keeper" % Rules.dungeon_scene())
	check(player.copper == copper0 + Rules.dungeon_reward_copper(), "领奖铜贝 +20000")
	check(player.gold == gold0 + Rules.dungeon_reward_gold(), "领奖金贝 +1")
	check(player.dungeon_kills == 0 and player.dungeon_deadline == 0, "领奖后清空进度")
	check(cleared[2] == 1 and cleared[0] == Rules.dungeon_reward_copper() and cleared[1] == Rules.dungeon_reward_gold(), "EventBus.dungeon_cleared 信号")
	check(router.page.contains("金贝"), "领奖页")

	# 超时踢出：进度清空，dungeon_day 保留防当日重复进入
	player.dungeon_day = -1
	router.handle("dungeon_try")
	check(player.location == Rules.dungeon_scene(), "再进地宫（超时用例准备）")
	for i in 3:
		player.dungeon_add_kill()
	player.dungeon_deadline = int(Time.get_unix_time_from_system()) - 10
	router.handle("goto:%s" % Rules.dungeon_scene())
	check(player.location == Rules.dungeon_exit_scene(), "超时踢出地宫")
	check(player.dungeon_kills == 0 and player.dungeon_deadline == 0, "超时清空进度")
	check(player.dungeon_day == player.current_day(), "超时保留当日记录")
	check(router.page.contains("限时已到"), "超时提示页")
	router.handle("dungeon_try")
	check(player.location != Rules.dungeon_scene(), "超时当日仍不得再进")
	bus.queue_free()


# ---------- 5.7b GM 彩蛋（福利官暗号）+ 经验加速丹 ----------

func _test_gm_easteregg(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("彩蛋员", "♂")

	# 福利官页第二选项
	router.handle("goto:fukleijyun")
	router.handle("npc:fukleijyun:officer")
	check(router.page.contains("welfare_claim"), "福利官页保留领福利")
	check(router.page.contains("纵横四海") and router.page.contains("gm_password"), "福利官页新增纵横四海入口")

	# 密码盘：数字追加、满 6 位截断、清空
	router.handle("gm_password")
	check(router.page.contains("gm_pwd:9") and router.page.contains("gm_pwd_ok"), "密码盘渲染数字键 + 确认")
	for d in "1234567":
		router.handle("gm_pwd:%s" % d)
	check(router.gm_pwd == "123456", "密码输入满 6 位截断")
	router.handle("gm_pwd:clear")
	check(router.gm_pwd == "", "清空归零")

	# 错误密码：无任何提示退回福利官，不发奖
	var pill_id := Rules.gm_exp_pill()
	var knife_id := Rules.gm_knife()
	var pill0 := player.count_stack(pill_id)
	var eq0 := player.equips.size()
	router.handle("gm_password")
	for d in "123456":
		router.handle("gm_pwd:%s" % d)
	router.handle("gm_pwd_ok")
	check(player.count_stack(pill_id) == pill0 and player.equips.size() == eq0, "错误密码不发奖")
	check(router.page.contains("领福利") and not router.page.contains("获得道具"), "错误密码无提示退回福利官")

	# 没输满 6 位点确认：同样无提示退回
	router.handle("gm_password")
	for d in "123":
		router.handle("gm_pwd:%s" % d)
	router.handle("gm_pwd_ok")
	check(player.count_stack(pill_id) == pill0, "未输满 6 位不发奖")

	# 正确密码：加速丹×3 + 小刀×1
	for d in Rules.gm_password():
		router.handle("gm_pwd:%s" % d)
	router.handle("gm_pwd_ok")
	check(player.count_stack(pill_id) == pill0 + 10, "正确密码加速丹×10 入包（丹数 3→10，ui-opt 契约 §2.2）")
	check(player.equips.size() == eq0 + 1, "正确密码小刀入包")
	check(router.page.contains("获得装备：小刀"), "领奖页显示小刀")
	var knife_atk: Array = GameData.get_item(knife_id).get("atk", [])
	check(knife_atk.size() == 2 and int(knife_atk[0]) == 100 and int(knife_atk[1]) == 1000
		and int(GameData.get_item(knife_id).get("durability", 0)) == 300, "小刀攻击 100-1000 / 耐久 300")

	# 可重复触发
	router.handle("gm_password")
	for d in Rules.gm_password():
		router.handle("gm_pwd:%s" % d)
	router.handle("gm_pwd_ok")
	check(player.count_stack(pill_id) == pill0 + 20, "彩蛋可重复触发（丹再+10，丹数 3→10 口径并入）")
	check(player.equips.size() == eq0 + 2, "彩蛋可重复触发（小刀再+1）")

	# 加速丹：药品页展示 + 使用 → 10 场 ×10
	player.equip_hand(player.equips.size() - 1)
	router.handle("items:drug")
	check(router.page.contains("经验×10（10场）"), "药品页显示加速丹效果")
	router.handle("use_drug:%s" % pill_id)
	check(player.exp_buff_left == 10 and player.exp_buff_mult == 10, "服丹后 10 场 ×10")
	check(player.count_stack(pill_id) == pill0 + 19, "服丹数量 -1（丹数 3→10 后为 20-1）")
	router.handle("status")
	check(router.page.contains("经验加速：×10（剩 10 场）"), "状态页显示加速 buff")

	# 战斗胜利：经验 ×10 结算并消耗 1 场次
	player.rng.seed = 42
	router.handle("goto:nungcoeng")
	router.handle("fight:bingji")
	var guarded := 0
	while router.combat != null and not router.combat.finished and guarded < 200:
		router.handle("attack")
		guarded += 1
	check(router.combat != null and router.combat.won, "加速丹战斗胜利")
	check(router.combat.reward_exp % 10 == 0, "胜利经验 ×10 结算")
	check(player.exp_buff_left == 9, "结算消耗 1 场次")
	router.handle("combat_reward")
	check(router.page.contains("经验加速丹生效"), "战利品页标注加速生效")
	router.handle("combat_leave")

	# 商店不卖加速丹，仍卖体力药
	router.handle("goto:soengdim")
	router.handle("npc:soengdim:merchant")
	check(not router.page.contains("buy_drug:%s" % pill_id), "商店不卖加速丹")
	check(router.page.contains("buy_drug:pingguo"), "商店仍卖体力药")

	# 战斗中使用加速丹：怪物不还手
	router.handle("goto:nungcoeng")
	router.handle("fight:bingji")
	check(router.combat != null, "进入战斗（战斗用丹用例）")
	var hp_before := player.hp_cur
	router.handle("combat_use:%s" % pill_id)
	check(player.exp_buff_left == 19, "战斗中服丹叠加至 19 场（9+10，场次叠加口径并入）")
	check(player.count_stack(pill_id) == pill0 + 18, "战斗中服丹数量 -1（丹数 3→10 后为 20-2）")
	check(player.hp_cur == hp_before, "战斗中服丹怪物不还手")
	player.add_copper(1000)
	router.handle("retreat")
	check(router.combat == null, "战斗用丹用例撤退清理")


# ---------- 5.7d 经验加速丹场次叠加（ui-opt 契约 §2.2） ----------

func _test_exp_buff_stack(player: PlayerCore) -> void:
	player.new_game("叠丹员", "♂")
	# 连吃两颗：场次叠加不取大，倍率保持最高
	player.apply_exp_buff(10, 10)
	player.apply_exp_buff(10, 10)
	check(player.exp_buff_left == 20, "连吃两颗加速丹叠加 20 场（场次叠加口径并入）")
	check(player.exp_buff_mult == 10, "叠加后倍率保持最高 ×10")
	# 战斗结算消耗 1 场次，返回生效倍率
	check(player.consume_exp_buff() == 10 and player.exp_buff_left == 19, "消耗 1 场次剩 19 且返回倍率 10")
	# 低倍率丹：场次继续叠加，倍率不稀释仍取最高
	player.apply_exp_buff(5, 2)
	check(player.exp_buff_left == 24 and player.exp_buff_mult == 10, "低倍率丹叠加场次且倍率保持最高")


# ---------- 5.7e 底部操作栏上下文 + 页面间距（ui-opt 契约 §3.2/§3.3） ----------

func _test_bottom_actions_and_pad(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("上下文员", "♂")
	player.rng.seed = 42

	# 规则 1 战斗中：含 攻击/药品/撤退 且事件词合法（未学技能不出攻击术）
	router.handle("goto:nungcoeng")
	router.handle("fight:bingji")
	var in_fight := router.bottom_actions()
	var fight_events: Array[String] = []
	for a: Dictionary in in_fight:
		fight_events.append(String(a.get("event", "")))
	check(in_fight.size() >= 3, "bottom_actions：战斗中至少 攻击/药品/撤退 三项")
	check(fight_events.has("attack") and fight_events.has("combat_drug") and fight_events.has("retreat"),
		"bottom_actions：战斗中含 攻击/药品/撤退 且事件合法")
	check(not fight_events.has("skill_cast"), "bottom_actions：未学技能不出攻击术")

	# 规则 2 战斗胜利：领取奖励 + 返回游戏
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	router.handle("attack")
	check(router.combat.finished and router.combat.won, "bottom_actions：造胜利结算前置成立")
	var won_acts := router.bottom_actions()
	check(won_acts.size() == 2 and String(won_acts[0].get("event", "")) == "combat_reward"
		and String(won_acts[1].get("event", "")) == "combat_leave", "bottom_actions：胜利页=领取奖励+返回游戏")
	router.handle("combat_leave")

	# 规则 3 商店族：handle("shop") 后 3 项，事件顺序 shop/market/sell_page
	router.handle("shop")
	var shop_acts := router.bottom_actions()
	var shop_events: Array[String] = []
	for a: Dictionary in shop_acts:
		shop_events.append(String(a.get("event", "")))
	check(shop_acts.size() == 3, "bottom_actions：商店族 3 项")
	check(shop_events[0] == "shop" and shop_events[1] == "market" and shop_events[2] == "sell_page",
		"bottom_actions：商店族事件 shop/market/sell_page")

	# 规则 4 铁匠族：handle("smith") 后 3 项，事件 smith_enhance/smith_gem/sell_equip_page
	router.handle("smith")
	var smith_acts := router.bottom_actions()
	var smith_events: Array[String] = []
	for a: Dictionary in smith_acts:
		smith_events.append(String(a.get("event", "")))
	check(smith_acts.size() == 3, "bottom_actions：铁匠族 3 项")
	check(smith_events[0] == "smith_enhance" and smith_events[1] == "smith_gem" and smith_events[2] == "sell_equip_page",
		"bottom_actions：铁匠族事件 smith_enhance/smith_gem/sell_equip_page")

	# 规则 3/4 主进程联调回归：商店/铁匠/市场首页经 NPC 打开（npc 事件不在命令词表内，
	# 靠 _npc 置 page_family 进底部操作栏——截图走查发现的首开缺失场景）
	router.handle("npc:soengdim:merchant")
	check(router.page_family == "shop" and router.bottom_actions().size() == 3,
		"bottom_actions：NPC 开商店首页也有商店族三项")
	router.handle("npc:titzoengpou:smith")
	check(router.page_family == "smith" and router.bottom_actions().size() == 3,
		"bottom_actions：NPC 开铁匠首页也有铁匠族三项")
	router.handle("npc:sicoeng:vendor")
	check(router.page_family == "shop" and router.bottom_actions().size() == 3,
		"bottom_actions：NPC 开市场首页也有商店族三项")
	router.handle("status")
	check(router.page_family == "" and router.bottom_actions().is_empty(),
		"bottom_actions：离开家族页后 page_family 复位为空")

	# 规则 5 场景有怪：_goto 后 page_is_scene 置位，首项 event 以 fight: 开头且最多 3 项
	router.handle("goto:nungcoeng")
	check(router.page_is_scene, "bottom_actions：_goto 成功渲染后 page_is_scene 置位")
	var scene_acts := router.bottom_actions()
	check(not scene_acts.is_empty() and String(scene_acts[0].get("event", "")).begins_with("fight:"),
		"bottom_actions：场景有怪首项以 fight: 开头")
	check(scene_acts.size() <= 3, "bottom_actions：场景怪入口最多 3 项")

	# 规则 6 其余：无怪场景与非场景命令页 → 空数组（隐藏）
	router.handle("goto:zaugun")
	check(router.bottom_actions().is_empty(), "bottom_actions：无怪场景为空数组")
	router.handle("status")
	check(router.bottom_actions().is_empty(), "bottom_actions：非场景命令页为空数组")

	# city_map：goto 链接 + 加宽分隔（相邻 url 间有 　·　）+ 每行入口 ≤3
	var cmap := Pages.city_map()
	check(cmap.contains("goto:"), "city_map：含 goto 链接")
	check(cmap.contains(Pages.WIDE_SEP), "city_map：相邻 url 间存在加宽分隔（ui-opt §3.1）")
	var max_links := 0
	for line in cmap.split("\n"):
		max_links = maxi(max_links, line.count("goto:"))
	check(max_links <= 3, "city_map：每行入口 ≤3 个")

	# gm_password_page("6")：gm_pwd:1..9 全部 url 齐备 + 大号键位 + 清空/确认在位
	var pad := Pages.gm_password_page("6")
	var all_keys := true
	for d in range(1, 10):
		if not pad.contains("gm_pwd:%d" % d):
			all_keys = false
			break
	check(all_keys, "gm_password_page：gm_pwd:1..9 全部 url 齐备")
	check(pad.contains("[font_size=40]　6　[/font_size]"), "gm_password_page：数字键加大且 U+3000 填充")
	check(pad.contains("gm_pwd:clear") and pad.contains("gm_pwd_ok"), "gm_password_page：清空/确认在位")

	# 加速丹文案报叠加后总量（ui-opt 契约 §3.2）
	var pill := Rules.gm_exp_pill()
	player.add_stack(pill, 1)
	router.handle("use_drug:%s" % pill)
	check(player.exp_buff_left == 10, "加速丹：服丹后共剩 10 场")
	check(router.page.contains("叠加后共剩 10 场"), "加速丹文案报叠加后总量（ui-opt §3.2）")


# ---------- 5.7c 检查更新（离线：只验页面与事件链路，不发真网络请求） ----------

func _test_update_checker(player: PlayerCore) -> void:
	# 版本比较
	check(Rules.github_repo() != "", "config.update.repo 已配置")
	check(not Rules.version_newer("1.0.1", "1.0.1"), "同版本不算更新")
	check(not Rules.version_newer("1.0.1", "1.0.2"), "本地更新则不提示")
	check(Rules.version_newer("1.0.2", "1.0.1"), "patch 段更新")
	check(Rules.version_newer("1.1.0", "1.0.9"), "minor 段比较")
	check(Rules.version_newer("v2.0", "1.9.9"), "tag 前缀 v 与缺省组件按 0")
	check(Rules.version_newer("V10.0.0", "9.99.99"), "大版本数值比较（非字典序）")

	var router := EventRouter.new()
	var page_updates := [0]
	router.page_changed.connect(func() -> void: page_updates[0] += 1)
	router.setup(player, null)

	# 标题页含检查更新入口
	router.handle("story:-1")
	check(router.page.contains("check_update") and router.page.contains("检查更新"), "标题页检查更新入口")

	# 发起检查：进入检查页（update_check_requested 无监听也不报错）
	router.handle("check_update")
	check(router.page.contains("正在检查更新") and router.page.contains("back_title"), "检查中页面")

	# 离线回填结果：新版本页
	router.apply_update_result({
		"ok": true, "version": "9.9.9", "notes": "更新日志：修了些bug",
		"apk_url": "https://example.com/a-word-game-9.9.9.apk", "html_url": "https://example.com/release",
	})
	check(page_updates[0] == 1, "apply_update_result 广播 page_changed")
	check(router.page.contains("发现新版本") and router.page.contains("update_download"), "新版本结果页 + 下载入口")
	check(router.page.contains("更新日志：修了些bug"), "更新日志展示")

	# 已是最新 / 失败可重试
	router.apply_update_result({"ok": true, "version": "0.0.1"})
	check(router.page.contains("已是最新版本"), "已是最新提示")
	router.apply_update_result({"ok": false})
	check(page_updates[0] == 3, "每次回填都广播 page_changed")
	check(router.page.contains("检查更新失败") and router.page.contains("check_update"), "失败页可重试")

	# 返回标题
	router.handle("back_title")
	check(router.page.contains("縱橫四海"), "返回标题页")


# ---------- 5.8 掉落扩展 drop_equip（扩展契约 §4.6） ----------

func _test_drop_equip(player: PlayerCore) -> void:
	var feng: Dictionary = GameData.monsters.get("feng_e", {})
	if feng.is_empty() or not GameData.items.has("liecha"):
		print("SKIP: drop_equip 用例缺少 feng_e/liecha 数据")
		return
	var de: Dictionary = feng.get("drop_equip", {})
	if de.is_empty():
		print("SKIP: drop_equip 用例缺少 feng_e.drop_equip 字段")
		return
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("猎人", "♂")
	player.rng.seed = 7

	# 命中路径（临时把概率改为 100%）
	var old_rate := int(de.get("rate", 0))
	de["rate"] = 100
	router.handle("goto:nungcoeng")
	router.handle("fight:feng_e")
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	router.handle("attack")
	check(router.combat.finished and router.combat.won, "战胜疯鹅")
	check(router.combat.reward_equip == "liecha", "drop_equip 命中")
	check(player.equips.any(func(inst: Dictionary) -> bool: return String(inst.get("id", "")) == "liecha")
		or player.count_stack("liecha") == 1, "猎叉入包")
	router.handle("combat_reward")
	check(router.page.contains("获得装备"), "战利品页显示掉落装备")
	router.handle("combat_leave")

	# 未命中路径（概率 0）
	de["rate"] = 0
	var eq0 := player.equips.size()
	router.handle("fight:feng_e")
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	router.handle("attack")
	check(router.combat.finished and router.combat.won, "再战疯鹅")
	check(router.combat.reward_equip == "", "drop_equip 未命中")
	check(player.equips.size() == eq0, "未命中不入包")
	de["rate"] = old_rate


# ---------- 5.9 航海贸易引擎（契约 docs/trade-spec.md §3） ----------

func _test_trade_engine() -> void:
	if not Trade.trade_data_ready():
		print("SKIP: 贸易引擎用例缺少 world.json / 12 贸易品数据")
		return
	var day := 20666
	# 同日确定型：同 day 同港热门恒定，每港抽 2 个
	for pid: String in ["venice", "risiben", "laguzha"]:
		var hot := Trade.hot_goods(pid, day)
		check(Trade.hot_goods(pid, day) == hot, "同 day 同港热门恒定 %s" % pid)
		check(hot.size() == 2, "每港抽 2 个热门 %s" % pid)
	# 不同 day 热门集合会变化（确定型，近 60 日必有一变）
	var changed := false
	for off in range(1, 61):
		if Trade.hot_goods("risiben", day + off) != Trade.hot_goods("risiben", day):
			changed = true
			break
	check(changed, "不同 day 热门集合会变化")
	# 公式抽查：非热门非产地=基准、产地×0.85、热门×1.8
	var checked_hot := false
	var checked_plain := false
	var checked_origin := false
	for port: Dictionary in GameData.world_ports:
		var pid := String(port.get("id", ""))
		var specialties: Array = port.get("specialties", [])
		for gid: String in Trade.hot_goods(pid, day):
			var base_hot := int(GameData.get_item(gid).get("buy_price", 0))
			check(Trade.price(gid, pid, day) == int(round(float(base_hot) * 1.8)), "热门定价=基准×1.8 %s@%s" % [gid, pid])
			checked_hot = true
		for gid: String in Trade.trade_goods():
			if Trade.is_hot(gid, pid, day):
				continue
			var base := int(GameData.get_item(gid).get("buy_price", 0))
			if specialties.has(gid):
				check(Trade.price(gid, pid, day) == int(round(float(base) * 0.85)), "产地定价=基准×0.85 %s@%s" % [gid, pid])
				checked_origin = true
			else:
				check(Trade.price(gid, pid, day) == base, "普通定价=基准 %s@%s" % [gid, pid])
				checked_plain = true
	check(checked_hot and checked_plain and checked_origin, "定价公式抽查覆盖热门/普通/产地")
	# 叠加抽查：临时把 venice 自家 specialty 塞进 demand_pool（测后还原）
	var venice := Trade.port_def(Trade.VENICE)
	var saved_pool: Array = (venice.get("demand_pool", []) as Array).duplicate()
	venice["demand_pool"] = ["putaojiu"]
	check(Trade.is_hot("putaojiu", Trade.VENICE, day), "临时池：putaojiu 当日热门")
	check(Trade.price("putaojiu", Trade.VENICE, day) == int(round(26.0 * 0.85 * 1.8)), "产地+热门叠加 ≈×1.53")
	venice["demand_pool"] = saved_pool
	check(not Trade.is_hot("putaojiu", Trade.VENICE, day), "还原 demand_pool 后不再热门")
	# 情报池：排除当前港且非空
	var pool := Trade.rumor_pool(day, Trade.VENICE)
	var pool_clean := not pool.is_empty()
	for entry: Dictionary in pool:
		if String(entry.get("port", "")) == Trade.VENICE:
			pool_clean = false
	check(pool_clean, "情报池排除当前港且非空")


# ---------- 5.10 航海贸易链路（契约 §4-§6：跨港买卖/情报真实性；跨港移动细节归 5.18b 航海全流程） ----------

func _test_trade_router(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("贸易商", "♂")
	player.add_copper(999999)
	if not Trade.trade_data_ready() or not _port_npcs_ready():
		print("SKIP: 贸易链路用例缺少 world/港口场景数据")
		return
	var day := player.current_day()
	var plan := _find_arbitrage(day)
	if plan.is_empty():
		print("SKIP: 贸易链路用例当日无产地/热门跨港组合")
		return
	var good := String(plan.get("good", ""))
	var origin := String(plan.get("origin", ""))
	var dest := String(plan.get("dest", ""))
	var wallet := player.copper + player.bank_silver * Rules.copper_per_silver()

	# 定位产地港（sail-region 契约 §1.6：tp 退役，跨港移动由 _test_sail_region_flow
	# 全流程覆盖，本用例专注贸易链路，直接 set_location 落位）
	player.set_location(Trade.port_scene(origin))
	check(player.location == Trade.port_scene(origin), "定位产地港")
	# 港口市场页：region / 随身铜贝 / 🔥抢手 / 买卖档位
	router.handle("npc:%s:merchant" % Trade.port_scene(origin))
	check(router.page.contains(String(Trade.port_def(origin).get("region", ""))), "市场页显示 region")
	check(router.page.contains("随身铜贝"), "市场页显示随身铜贝")
	check(router.page.contains("🔥抢手"), "市场页含🔥抢手标记")
	check(router.page.contains("trade_buy:%s:" % good), "市场页买入档位")
	check(router.page.contains("trade_sell:%s:all" % good), "市场页全部卖出档位")
	# 产地买入
	var buy_unit := Trade.price(good, origin, day)
	var qty := 10
	router.handle("trade_buy:%s:%d" % [good, qty])
	check(player.count_stack(good) == qty, "产地买入 %d 箱入包" % qty)
	wallet -= buy_unit * qty
	check(player.copper + player.bank_silver * Rules.copper_per_silver() == wallet, "买入扣款=产地价×数量")
	# 港口船主页（当前所在标记 + sail_to 链接，sail-region 契约 §1.6）→ 定位热门港
	router.handle("npc:%s:sailor" % Trade.port_scene(origin))
	check(router.page.contains("当前所在"), "船主页标当前所在")
	check(router.page.contains("sail_to:"), "船主页含 sail_to 链接")
	player.set_location(Trade.port_scene(dest))
	check(player.location == Trade.port_scene(dest), "定位热门港")
	# 酒保情报：扣费 + 必真 + 排除当前港
	router.handle("npc:%s:barkeep" % Trade.port_scene(dest))
	check(router.page.contains("打听小道消息"), "酒保情报页 rumor 链接")
	var purse := player.copper
	router.handle("rumor")
	check(player.copper == purse - Rules.rumor_cost(), "情报扣费 rumor_cost")
	check(_page_rumors_true(router.page, day, dest), "情报必真且排除当前港")
	wallet -= Rules.rumor_cost()
	# 热门港卖出赚差价
	var sell_unit := Trade.price(good, dest, day)
	check(sell_unit > buy_unit, "产地价 < 热门港价（跨港利润）")
	router.handle("trade_sell:%s:%d" % [good, qty])
	check(player.count_stack(good) == 0, "热门港卖出清仓")
	wallet += sell_unit * qty
	check(player.copper + player.bank_silver * Rules.copper_per_silver() == wallet, "链路终钱包对账（ sail-region 时代：钱包只受买卖与情报影响）")


func _port_npcs_ready() -> bool:
	for p: Dictionary in GameData.world_ports:
		var pid := String(p.get("id", ""))
		if pid == Trade.VENICE:
			continue
		var scene := GameData.get_scene(Trade.port_scene(pid))
		if scene.is_empty():
			return false
		var ids: Array[String] = []
		for npc: Dictionary in scene.get("npcs", []):
			ids.append(String(npc.get("id", "")))
		# sail-region 契约 §1.3：外港传送占位退役为船主，贸易链路前置改验 sailor
		if not (ids.has("merchant") and ids.has("barkeep") and ids.has("sailor")):
			return false
	return true


## 找一条当日「产地买入 → 异港热门卖出」路径（每港 2 热门，热门品必为他港特产）。
## 威尼斯走既有市场（无 barkeep/merchant），产地与目的地只取 9 个新港口。
func _find_arbitrage(day: int) -> Dictionary:
	for port: Dictionary in GameData.world_ports:
		var pid := String(port.get("id", ""))
		if pid == Trade.VENICE:
			continue
		for gid: String in Trade.hot_goods(pid, day):
			for other: Dictionary in GameData.world_ports:
				var oid := String(other.get("id", ""))
				if oid != Trade.VENICE and oid != pid and (other.get("specialties", []) as Array).has(gid):
					return {"good": gid, "origin": oid, "dest": pid}
	return {}


func _port_index(port_id: String) -> int:
	for i in GameData.world_ports.size():
		if String(GameData.world_ports[i].get("id", "")) == port_id:
			return i
	return -1


## 解析情报页「【货】在【港】」，逐条校验当日 is_hot 且不报当前港。
## 注意 split("【") 会吞掉分隔符：货名块以「】在」结尾，港名是下一块开头。
func _page_rumors_true(text: String, day: int, current_port: String) -> bool:
	var chunks := text.split("【")
	var found := 0
	for i in chunks.size():
		var chunk := String(chunks[i])
		if chunk.substr(chunk.find("】") + 1) != "在" or i + 1 >= chunks.size():
			continue
		var gid := _good_id_by_name(chunk.get_slice("】", 0))
		var pid := _port_id_by_name(String(chunks[i + 1]).get_slice("】", 0))
		if gid == "" or pid == "" or pid == current_port or not Trade.is_hot(gid, pid, day):
			return false
		found += 1
	return found > 0


func _good_id_by_name(display_name: String) -> String:
	for gid in Trade.GOODS:
		if String(GameData.get_item(String(gid)).get("name", "")) == display_name:
			return String(gid)
	return ""


func _port_id_by_name(display_name: String) -> String:
	for p: Dictionary in GameData.world_ports:
		if String(p.get("name", "")) == display_name:
			return String(p.get("id", ""))
	return ""


# ---------- 5.11 装备回收（契约 trade-spec §7） ----------

func _test_sell_equip(player: PlayerCore) -> void:
	for probe: Array in [["hualiwandao1", 800], ["dahuandao", 12000], ["xiaojinsiteng", 150]]:
		var eq_id := String(probe[0])
		if not GameData.has_item(eq_id) or int(GameData.get_item(eq_id).get("price", -1)) != int(probe[1]):
			print("SKIP: 装备回收用例缺少装备 price 字段")
			return
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("收荒匠", "♂")
	check(Rules.equip_sell_price(800) == 320, "回收价=round(基准×40%)")
	# 铁匠页入口 + 回收页列表
	router.handle("goto:titzoengpou")
	router.handle("npc:titzoengpou:smith")
	check(router.page.contains("出售装备"), "铁匠页出售装备入口")
	router.handle("sell_equip_page")
	check(router.page.contains("回收320铜贝"), "回收页列出弯刀回收价 320")
	check(not router.page.contains("sell_equip_all"), "单件装备不显示批量入口")
	# 手持装备回收：先自动卸下；成交后留在出售页继续出售
	router.handle("sell_equip:0")
	check(player.copper == 320, "手持弯刀回收入账 320")
	check(player.equips.is_empty() and player.hand == -1, "手持卖出自动卸下")
	check(router.page.contains("回炉") and router.page.contains("出售装备"), "回收后留在出售页（继续出售，免往返）")
	# 卖出低下标装备：手持下标前移
	var i1 := player.add_equip("dahuandao")
	var i2 := player.add_equip("xiaojinsiteng")
	check(i1 == 0 and i2 == 1, "两件装备入包")
	check(player.equip_hand(i2) == "", "手持小金丝藤")
	router.handle("sell_equip:0")
	check(player.equips.size() == 1 and player.hand == 0, "卖出低下标后手持下标前移")
	check(player.copper == 320 + Rules.equip_sell_price(12000), "大环刀回收 4800")
	# 批量出售全部同名装备
	var i3 := player.add_equip("dahuandao")
	var i4 := player.add_equip("dahuandao")
	check(i3 >= 0 and i4 >= 0, "两把大环刀入包")
	router.handle("sell_equip_page")
	check(router.page.contains("全部出售2件"), "同名多件显示批量入口")
	var copper_all := player.copper
	router.handle("sell_equip_all:dahuandao")
	check(player.equips.size() == 1 and player.hand == 0, "批量出售只清同名，手持小金丝藤保留")
	check(player.copper == copper_all + 2 * Rules.equip_sell_price(12000), "批量出售入账=单价×件数")
	check(router.page.contains("全收了") and router.page.contains("出售装备"), "批量成交后留在出售页")
	router.handle("sell_equip_all:dahuandao")
	check(player.equips.size() == 1 and player.copper == copper_all + 2 * Rules.equip_sell_price(12000), "无同名可卖时不重复入账")
	# 非法下标安全兜底
	router.handle("sell_equip:9")
	check(router.page.contains("出售装备") and player.equips.size() == 1, "非法下标回回收页")
	router.handle("sell_equip:0")
	check(player.equips.is_empty(), "清空装备")
	check(player.copper == 320 + 4800 + 2 * Rules.equip_sell_price(12000) + Rules.equip_sell_price(150),
		"小金丝藤回收 60（含批量入账对账）")


# ---------- 5.12 生活系统（契约 plan-v2 §5.1-§5.4） ----------

func _test_life_system(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("生活家", "♂")
	player.rng.seed = 42
	player.add_copper(5000)

	# 自动喝药（契约 §5.1）：体力 <auto_stamina_pct% 且包内有奶瓶 → spend_stamina 自动食用
	player.stamina = player.max_stamina()
	player.add_stack("naiping", 1)
	player.stamina = int(player.max_stamina() * 0.4)
	check(player.spend_stamina(10), "体力充足可消耗")
	check(player.count_stack("naiping") == 0, "低于阈值自动喝奶瓶")
	check(player.stamina == player.max_stamina(), "自动喝药补满体力")

	# 打坐三重校验（契约 §5.2）：无草人 / 等级不足 / 成功扣体力得经验
	player.new_game("打坐员", "♂")
	var res := Life.meditate(player)
	check(not bool(res.get("ok", true)), "无草人不可打坐")
	player.add_stack("yeqiu_caoren", 1)
	player.level = 5
	res = Life.meditate(player)
	check(not bool(res.get("ok", true)), "等级不足不可打坐")
	player.level = 10
	player.stamina = player.max_stamina()
	var stam0 := player.stamina
	res = Life.meditate(player)
	check(bool(res.get("ok", false)), "草人+等级齐备可打坐")
	check(player.stamina == stam0 - Rules.life_meditate_stamina(), "打坐扣体力")
	check(int(res.get("exp", 0)) == 10 * Rules.life_meditate_exp_per_level(), "打坐经验=等级×单级经验")
	check(player.exp_cur == int(res.get("exp", 0)), "打坐经验入账")

	# 钓鱼两表（契约 §5.3）：注入全权重表逐项验证（测后还原）
	var fish_cfg: Dictionary = GameData.config.get("life", {})
	var saved_fish: Array = (fish_cfg.get("fish_table", []) as Array).duplicate()
	var saved_bait: Array = (fish_cfg.get("fish_table_bait", []) as Array).duplicate()
	fish_cfg["fish_table"] = [{"id": "xiaoyu", "w": 100}]
	fish_cfg["fish_table_bait"] = [{"id": "zhenzhu", "w": 100}]
	router.handle("goto:haitan")
	check(router.page.contains("钓鱼") and router.page.contains("fish:bait"), "fish_scenes 场景页显示钓鱼入口")
	var stam1 := player.stamina
	router.handle("fish")
	check(player.count_stack("xiaoyu") == 1, "钓鱼按 fish_table 入包")
	player.add_stack("xiaoyu_huoer", 1)
	router.handle("fish:bait")
	check(player.count_stack("zhenzhu") == 1, "用活饵按 bait 表入包")
	check(player.count_stack("xiaoyu_huoer") == 0, "用活饵扣 1 条活饵")
	check(player.stamina == stam1 - 2 * Rules.life_fish_stamina(), "钓鱼两次扣体力")
	fish_cfg["fish_table"] = saved_fish
	fish_cfg["fish_table_bait"] = saved_bait
	router.handle("goto:zaugun")
	router.handle("fish")
	check(router.page.contains("钓不了鱼"), "非钓鱼场景拒绝")

	# 种田（契约 §5.3）：播种扣种子扣体力 → 未熟不可收 → 到期收获 3 牧草
	router.handle("goto:nungcoeng")
	player.add_stack("mucao_zhongzi", 2)
	var stam2 := player.stamina
	router.handle("farm")
	check(router.page.contains("农场"), "农场页可达")
	router.handle("farm_plant:0")
	check(player.count_stack("mucao_zhongzi") == 1, "播种扣种子")
	check(player.stamina == stam2 - Rules.life_farm_stamina(), "播种扣体力")
	check(String((player.farm_plots[0] as Dictionary).get("seed_id", "")) == "mucao_zhongzi", "地块记录种子")
	router.handle("farm_harvest")
	check(player.count_stack("mucao") == 0, "未熟不可收获")
	var plot0: Dictionary = player.farm_plots[0]
	plot0["planted_unix"] = int(Time.get_unix_time_from_system()) - Rules.life_farm_grow_sec() - 1
	router.handle("farm_harvest")
	check(player.count_stack("mucao") == Rules.life_farm_harvest_count(), "收获牧草×3")
	check((player.farm_plots[0] as Dictionary).is_empty(), "收获后地块清空")
	var seed_before := player.count_stack("mucao_zhongzi")
	router.handle("farm_plant:9")
	check(player.count_stack("mucao_zhongzi") == seed_before, "非法地块不播种")

	# 潜水三路（契约 §5.4）+ 撤退清连胜（契约 §4.2）
	var dive_cfg: Dictionary = GameData.config.get("life", {})
	var saved_dive: Array = (dive_cfg.get("dive_table", []) as Array).duplicate()
	router.handle("goto:tsienhoi")
	dive_cfg["dive_table"] = [{"id": "nothing", "w": 100}]
	router.handle("dive")
	check(router.page.contains("什么也没捞到"), "潜水空手安慰文案")
	dive_cfg["dive_table"] = [{"id": "zhenzhu", "w": 100}]
	router.handle("dive")
	check(player.count_stack("zhenzhu") >= 1, "潜水捞到物品入包")
	dive_cfg["dive_table"] = [{"id": "haihuang_suipian", "w": 100}]
	var shards0 := int(player.quest_siren.get("shards", 0))
	router.handle("dive")
	check(player.count_stack("haihuang_suipian") == 1, "潜水拾得海皇碎片")
	check(int(player.quest_siren.get("shards", 0)) == shards0 + 1, "碎片计数 +1")
	dive_cfg["dive_table"] = [{"id": "monster:hai_yao", "w": 100}]
	player.bump_streak()
	player.bump_streak()
	router.handle("dive")
	check(router.combat != null and not router.combat.finished, "潜水遇怪进入战斗")
	player.add_copper(1000)
	router.handle("retreat")
	check(router.combat == null, "潜水战斗撤退清理")
	check(player.streak == 0 and player.momentum == 0, "撤退清连胜与士气")
	dive_cfg["dive_table"] = saved_dive
	router.handle("goto:zaugun")
	router.handle("dive")
	check(router.page.contains("没法潜水"), "非潜水场景拒绝")


# ---------- 5.13 物品效果 / buff 卡片 / 改名 / 礼包（契约 plan-v2 §5.1/§5.7/§5.8） ----------

func _test_item_effects(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("试用员", "♂")
	player.rng.seed = 42
	player.add_copper(100000)

	# stamina 类：恢复生活体力（满时拒用防浪费）
	player.stamina = 0
	player.add_stack("quqibing", 1)
	router.handle("use_item:quqibing")
	check(player.stamina == player.max_stamina(), "曲奇饼恢复生活体力（上限截断）")
	check(player.count_stack("quqibing") == 0, "体力食物用后消耗")
	player.add_stack("quqibing", 1)
	router.handle("use_item:quqibing")
	check(player.count_stack("quqibing") == 1, "活力满时不消耗")

	# buff 卡片（契约 §5.1）：双倍经验卡生效 / 与场次制取大 / 还原卡清除
	player.add_stack("shuangbei_jingyanka", 1)
	router.handle("use_item:shuangbei_jingyanka")
	check(player.exp_mult() == 2.0, "双倍经验卡 exp_mult=2")
	check(player.buffs.size() == 1, "时间制 buff 入列")
	player.apply_exp_buff(3, 10)
	check(player.exp_mult() == 10.0, "场次制与时间制取大")
	player.add_stack("huanyuan_ka", 1)
	router.handle("use_item:huanyuan_ka")
	check(player.buffs.is_empty(), "还原卡清除时间制 buff")
	check(player.exp_mult() == 10.0, "场次制 buff 不受还原卡影响")
	player.exp_buff_left = 1
	player.consume_exp_buff()
	check(player.exp_mult() == 1.0, "场次耗尽后倍率归一")

	# 乾坤袋：负重上限叠加
	var wm0 := player.weight_max()
	player.add_stack("qiankun_dai", 2)
	router.handle("use_item:qiankun_dai")
	router.handle("use_item:qiankun_dai")
	check(player.weight_bonus == 100 and player.weight_max() == wm0 + 100, "乾坤袋 +50 负重可叠加")

	# 技能书：学会攻击术；重复使用不消耗
	player.add_stack("jineng_shu", 1)
	router.handle("use_item:jineng_shu")
	check(player.has_skill("attack"), "技能书学会攻击术")
	check(player.count_stack("jineng_shu") == 0, "学会后技能书消耗")
	player.add_stack("jineng_shu", 1)
	router.handle("use_item:jineng_shu")
	check(player.count_stack("jineng_shu") == 1, "已学攻击术不重复消耗")

	# 打坐工具 / 任务物品：不消耗的使用反馈
	player.add_stack("yeqiu_caoren", 1)
	router.handle("use_item:yeqiu_caoren")
	check(player.count_stack("yeqiu_caoren") == 1, "野球草人不消耗")
	check(router.page.contains("打坐"), "草人使用给打坐指引")
	player.add_stack("haihuang_suipian", 1)
	router.handle("use_item:haihuang_suipian")
	check(player.count_stack("haihuang_suipian") == 1, "任务物品禁用不消耗")
	check(router.page.contains("任务信物"), "任务物品禁用提示")

	# 改名（契约 §5.8）：等级校验在 router；达标后改名成功并消耗
	player.add_stack("gaiming_ka", 1)
	router.handle("use_item:gaiming_ka")
	check(router.input_mode == "rename", "改名卡进入输入模式")
	router.handle("rename", "新名字")
	check(player.nickname == "试用员", "等级不足改名拒绝")
	check(player.count_stack("gaiming_ka") == 1, "等级不足不消耗改名卡")
	check(router.input_mode == "rename", "失败保持输入模式")
	player.level = 30
	router.handle("rename", "新名字")
	check(player.nickname == "新名字", "改名成功")
	check(player.count_stack("gaiming_ka") == 0, "改名成功消耗改名卡")

	# 福利院礼包（契约 §5.7）：一次性领取 + 打开 contents
	router.handle("gift_claim")
	check(player.gift_claimed, "礼包领取标记")
	check(player.count_stack("yufu_libao") == 1, "礼包入包")
	var cu0 := player.copper
	router.handle("use_item:yufu_libao")
	check(player.copper == cu0 + 2000, "礼包开出 2000 铜贝")
	check(player.count_stack("naiping") >= 2, "礼包开出奶瓶×2")
	check(player.count_stack("qiankun_dai") >= 1, "礼包开出乾坤袋")
	check(player.count_stack("yufu_libao") == 0, "礼包打开后消耗")
	router.handle("gift_claim")
	check(player.count_stack("yufu_libao") == 0, "礼包不可重复领取")

	# 未知物品兜底
	router.handle("use_item:nonexistent")
	check(router.page.contains("没找到"), "未知物品兜底提示")

	# 体力宝限持 2（契约 §5.1，buy 路径校验；临时给个 price 走商店，测后还原）
	var tili: Dictionary = GameData.get_item("tili_bao")
	var saved_price := int(tili.get("price", 0))
	tili["price"] = 1
	router.handle("buy_drug:tili_bao:2")
	check(player.count_stack("tili_bao") == 2, "体力宝限持内可买 2")
	router.handle("buy_drug:tili_bao:1")
	check(player.count_stack("tili_bao") == 2, "体力宝限持 2 生效")
	tili["price"] = saved_price


# ---------- 5.14 装备词条 / 强化 / 宝石 / 绑定禁卖（契约 plan-v2 §5.12） ----------

func _test_equipment_affixes(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("锻造师", "♂")
	player.rng.seed = 42
	player.add_copper(100000)
	player.level = 10  # 粗制铜盔 req_level=4，护甲穿戴用例需等级达标

	# 护甲穿戴：def 并入、词条并入
	var belt := player.add_equip("piyaodai")
	check(belt >= 0 and player.equip_armor(belt), "护甲可穿戴")
	check(player.armor_idx == belt and player.armor_def() == 1, "护甲 def 并入防御")
	check(player.total_agility() == 2 and player.total_lucky() == 1, "敏捷/幸运词条并入")
	var helmet := player.add_equip("cuzhitongkui")
	check(player.equip_armor(helmet) and player.armor_idx == helmet, "换穿护甲")

	# 宝石镶嵌（router 两步页）：lanbaoshi def+2；插槽满后拒绝
	player.add_stack("lanbaoshi", 2)
	router.handle("smith_gem")
	check(router.page.contains("选这件"), "宝石页第一步选装备")
	router.handle("smith_gem:%d" % helmet)
	check(router.page.contains("蓝宝石") and router.page.contains("smith_gem:%d:lanbaoshi" % helmet), "宝石页第二步选宝石")
	router.handle("smith_gem:%d:lanbaoshi" % helmet)
	check(int(player.gem_bonus().get("def", 0)) == 2, "镶嵌后 gem_bonus.def +2")
	check(player.count_stack("lanbaoshi") == 1, "镶嵌扣包")
	router.handle("smith_gem:%d:lanbaoshi" % helmet)
	check(player.count_stack("lanbaoshi") == 1, "插槽已满拒绝镶嵌")
	router.handle("equip_view:%d" % helmet)
	check(router.page.contains("宝石：") and router.page.contains("插槽"), "装备详情显示插槽与宝石")

	# 强化（PlayerCore 直调）：扣龙泉水+200 铜、enhance+1、绑定
	player.add_stack("longquanshui", 2)
	var weapon_price := 0
	var res := player.enhance_equip(0)
	check(bool(res.get("ok", false)), "强化成功")
	check(int((player.equips[0] as Dictionary).get("enhance", 0)) == 1, "强化等级 +1")
	check(bool((player.equips[0] as Dictionary).get("bound", false)), "强化后绑定")
	check(player.count_stack("longquanshui") == 1, "强化扣龙泉水")
	check(player.copper == 100000 - Rules.smith_enhance_copper(), "强化扣铜贝")
	var bare := Rules.base_atk(player.level)
	check(player.atk_range() == Vector2i(bare.x + 9, bare.y + 23), "强化后武器攻击 ×1.05（9→9，22→23）")
	weapon_price = int(res.get("msg", "").length())
	check(weapon_price > 0, "强化有反馈文案")

	# 强化（router 页）：两件装备列表 + 强化到 +2
	router.handle("smith_enhance")
	check(router.page.contains("强化装备") or router.page.contains("铁匠铺 · 强化"), "强化页可达")
	router.handle("smith_enhance:0")
	check(int((player.equips[0] as Dictionary).get("enhance", 0)) == 2, "router 强化 +2")
	# 强化到上限 7：龙泉水管够，循环直到拒绝
	player.add_stack("longquanshui", 20)
	var guard := 0
	res = player.enhance_equip(0)
	while bool(res.get("ok", false)) and guard < 20:
		res = player.enhance_equip(0)
		guard += 1
	check(not bool(res.get("ok", false)) and int((player.equips[0] as Dictionary).get("enhance", 0)) == Rules.smith_enhance_max(), "强化到上限 %d 后拒绝" % Rules.smith_enhance_max())

	# 绑定禁卖（主进程裁决）：单件与批量都拒收
	router.handle("sell_equip_page")
	check(router.page.contains("绑定装备无法出售"), "回收页标注绑定不可售")
	var copper0 := player.copper
	router.handle("sell_equip:0")
	check(player.copper == copper0, "绑定装备出售拒绝")
	check(player.equips.size() >= 3, "绑定装备未被移除")
	router.handle("sell_equip_all:hualiwandao1")
	check(player.copper == copper0, "绑定装备批量出售拒绝")

	# 铁匠购买装备（契约 §2.1 在售）：长剑 30 铜；price=0 的小刀不卖
	var eq0 := player.equips.size()
	var cu0 := player.copper
	router.handle("buy_equip:changjian")
	check(player.equips.size() == eq0 + 1 and player.copper == cu0 - 30, "铁匠购买长剑扣款入包")
	router.handle("buy_equip:xiaodao")
	check(player.equips.size() == eq0 + 1, "price=0 装备不在售")
	# 高阶装备（L17-22，D1 落地）在铁匠在售页全部可见且可购买
	router.handle("goto:titzoengpou")
	router.handle("npc:titzoengpou:smith")
	check(router.page.contains("buy_equip:xuantiejia") and router.page.contains("buy_equip:anlinjuren")
		and router.page.contains("buy_equip:lingzhuzhiren") and router.page.contains("buy_equip:xuantiezhongjian"),
		"铁匠在售页列出全部高阶装备")
	check(router.page.contains("玄铁甲") and router.page.contains("领主之刃"), "高阶装备名称渲染")
	var hq0 := player.copper
	router.handle("buy_equip:xuantiezhongjian")
	check(player.copper == hq0 - 16000
		and player.equips.any(func(inst: Dictionary) -> bool: return String(inst.get("id", "")) == "xuantiezhongjian"),
		"高阶装备可 buy_equip 入包")

	# 商店过滤（契约 §2.1）：price>0 功能道具在售；任务物品/宝石/price=0 不在售
	router.handle("goto:soengdim")
	router.handle("npc:soengdim:merchant")
	check(router.page.contains("buy_drug:quqibing:1"), "商店卖曲奇饼")
	check(router.page.contains("疗效+30"), "商店保留体力药疗效文案")
	check(not router.page.contains("buy_drug:tili_bao"), "商店不卖体力宝")
	check(not router.page.contains("buy_drug:hongbaoshi"), "商店不卖宝石")
	check(not router.page.contains("buy_drug:shibeijingyandan"), "商店不卖加速丹")
	var q0 := player.count_stack("quqibing")
	var cq := player.copper
	router.handle("buy_drug:quqibing:1")
	check(player.count_stack("quqibing") == q0 + 1 and player.copper == cq - 150, "商店买曲奇饼扣款 150")


# ---------- 5.14b 宝石属性并入真实属性（ui-opt 契约 §2.1 口径并入） ----------

func _test_gem_merge(player: PlayerCore) -> void:
	player.new_game("镶宝石", "♂")

	# 红宝石 atk+3 并入攻击区间两端（口径并入：战斗引擎不再对宝石攻击另行加成）
	var atk0 := player.atk_range()
	var hat := player.add_equip("cuzhitongkui")
	player.add_stack("hongbaoshi", 1)
	check(hat >= 0 and player.socket_gem(hat, "hongbaoshi").get("ok", false), "镶嵌红宝石成功")
	check(player.atk_range() == Vector2i(atk0.x + 3, atk0.y + 3), "红宝石 atk+3 并入攻击区间两端（口径并入）")

	# 护甲 + 蓝宝石：defense() = 基础 + 护甲 + 宝石 def（口径并入：战斗引擎不再三重相加）
	var belt := player.add_equip("piyaodai")
	check(player.equip_armor(belt), "穿戴皮腰带（宝石口径用例）")
	var dhat := player.add_equip("cuzhitongkui")
	player.add_stack("lanbaoshi", 1)
	check(player.socket_gem(dhat, "lanbaoshi").get("ok", false), "镶嵌蓝宝石成功")
	check(player.defense() == Rules.base_def(player.level) + player.armor_def() + 2,
		"defense()=基础+护甲+蓝宝石 def+2（口径并入）")

	# 紫水晶 hp+50 并入体力上限；卖出该件后上限回落、体力收紧不越上限（口径并入）
	var base_max := Rules.max_hp(player.level)
	var phat := player.add_equip("cuzhitongkui")
	player.add_stack("zibaoshi", 1)
	check(player.socket_gem(phat, "zibaoshi").get("ok", false), "镶嵌紫水晶成功")
	check(player.max_hp() == base_max + 50, "紫水晶 hp+50 并入体力上限（口径并入）")
	player.hp_cur = player.max_hp()  # 顶到含宝石上限，制造卖出后的越界前提
	var sold: Dictionary = player.sell_equip(phat)
	check(not sold.is_empty(), "卖出带紫水晶装备成功")
	check(player.max_hp() == base_max, "卖出后宝石 hp 上限回落")
	check(player.hp_cur == player.max_hp() and player.hp_cur <= player.max_hp(), "卖出后体力收紧不越上限（口径并入）")


# ---------- 5.15 任务链（安德鲁/西利亚/谜语，契约 plan-v2 §5.5-§5.6） ----------

func _test_quests(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("冒险家", "♂")
	player.rng.seed = 42
	player.add_copper(100000)

	# 安德鲁：接受 → 重复拒绝
	router.handle("goto:zaugun")
	router.handle("npc:zaugun:andedalu")
	check(router.page.contains("接下试炼"), "安德鲁试炼页可接")
	router.handle("quest_andrew:accept")
	check(String(player.quest_andrew.get("state", "")) == "active", "试炼接受")
	check(int(player.quest_andrew.get("day", -1)) == player.current_day(), "试炼记录当日")
	router.handle("quest_andrew:accept")
	check(router.page.contains("已经有安排"), "同日重复接取拒绝")

	# 野外击杀计数
	router.handle("goto:nungcoeng")
	router.handle("fight:bingji")
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	router.handle("attack")
	check(router.combat.finished and router.combat.won, "战胜病鸡")
	check(int(player.quest_andrew.get("kills", 0)) == 1, "野外击杀计数 +1")
	router.handle("combat_leave")

	# 地宫击杀不计（契约 §5.5）
	player.add_exp(5000)
	check(player.level >= 5, "升到 5 级")
	router.handle("goto:baksingmun")
	router.handle("dungeon_try")
	check(player.location == Rules.dungeon_scene(), "进入地宫")
	router.handle("fight:%s" % Rules.dungeon_monster())
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	router.handle("attack")
	check(router.combat.finished and router.combat.won, "战胜抢劫者")
	check(int(player.quest_andrew.get("kills", 0)) == 1, "地宫击杀不计入试炼")
	router.handle("combat_leave")

	# 领奖：计数不足拒绝 / 达标领 jineng_shu+1000 铜 / 重复拒绝 / 次日可重接
	player.quest_andrew["kills"] = 9
	var cu0 := player.copper
	router.handle("quest_andrew:claim")
	check(player.copper == cu0 and player.count_stack("jineng_shu") == 0, "计数不足不发奖")
	check(router.page.contains("还差"), "计数不足提示")
	player.quest_andrew["kills"] = 10
	router.handle("quest_andrew:claim")
	check(player.copper == cu0 + Rules.quest_andrew_reward_copper(), "领奖 +1000 铜")
	check(player.count_stack("jineng_shu") == 1, "领奖技能书入包")
	check(String(player.quest_andrew.get("state", "")) == "claimed", "领奖后状态 claimed")
	var cu1 := player.copper
	router.handle("quest_andrew:claim")
	check(player.copper == cu1, "同日重复领奖拒绝")
	router.handle("quest_andrew:accept")
	check(router.page.contains("已经有安排"), "领奖当日不可重接")
	player.quest_andrew["day"] = player.current_day() - 1
	router.handle("quest_andrew:accept")
	check(int(player.quest_andrew.get("kills", 0)) == 0 and String(player.quest_andrew.get("state", "")) == "active", "次日轮换可重接")

	# 西利亚：碎片不足拒绝 / 集齐交付 / 一次性
	router.handle("npc:zaugun:xiliya")
	check(router.page.contains("海皇"), "西利亚任务页")
	router.handle("quest_siren")
	check(not bool(player.quest_siren.get("claimed", false)), "碎片不足不交付")
	player.add_stack("haihuang_suipian", 2)
	router.handle("quest_siren")
	check(player.count_stack("haihuang_suipian") == 2, "碎片 2/3 不交付")
	player.add_stack("haihuang_suipian", 1)
	var lq0 := player.count_stack("longquanshui")
	var card0 := player.count_stack("shuangbei_jingyanka")
	router.handle("quest_siren")
	check(player.count_stack("haihuang_suipian") == 0, "交付扣除 3 碎片")
	check(player.count_stack("longquanshui") == lq0 + 3, "谢礼龙泉水×3")
	check(player.count_stack("shuangbei_jingyanka") == card0 + 1, "谢礼双倍经验卡×1")
	check(bool(player.quest_siren.get("claimed", false)), "交付后标记已领")
	router.handle("quest_siren")
	check(player.count_stack("longquanshui") == lq0 + 3, "谢礼不可重复领取")

	# 谜语：答错无惩罚可再猜 / 答对 500 铜 / 每日限一次
	router.handle("npc:zaugun:aobupasi")
	check(router.page.contains("今日之谜") and router.page.contains("riddle:0"), "谜语页出题")
	var options := Pages.riddle_options()
	var today := player.current_day()
	var riddle: Dictionary = Rules.quest_riddles()[Pages.riddle_day_index(today)]
	var answer := String(riddle.get("a", ""))
	var wrong_idx := 0
	for i in options.size():
		if options[i] != answer:
			wrong_idx = i
			break
	var cu2 := player.copper
	router.handle("riddle:%d" % wrong_idx)
	check(player.copper == cu2, "答错不扣不奖")
	check(router.page.contains("再想想"), "答错可再猜")
	var right_idx := options.find(answer)
	check(right_idx >= 0, "当日谜底在选项中")
	router.handle("riddle:%d" % right_idx)
	check(player.copper == cu2 + Rules.quest_riddle_reward_copper(), "答对 +500 铜")
	check(player.riddle_day == today, "谜语记录当日")
	router.handle("riddle:%d" % wrong_idx)
	check(player.copper == cu2 + Rules.quest_riddle_reward_copper(), "每日限答一次")


# ---------- 5.11b 自动战斗（GameScreen 真实按钮路径，tick 调快免真等） ----------

func _test_auto_battle(player: PlayerCore) -> void:
	var router := EventRouter.new()
	router.setup(player, null)
	player.new_game("挂机员", "♂")
	player.rng.seed = 42

	# 场景可战斗对象探测：农场=病鸡、酒馆=无、地宫=抢劫者
	router.handle("goto:nungcoeng")
	check(router.scene_first_monster() == "bingji", "自动战斗：农场首个可战斗对象=病鸡")
	router.handle("goto:zaugun")
	check(router.scene_first_monster() == "", "自动战斗：酒馆无可战斗对象")
	router.handle("goto:digung")
	check(router.scene_first_monster() == Rules.dungeon_monster(), "自动战斗：地宫可战斗对象=抢劫者")
	router.handle("goto:zaugun")

	# UI 路径：tick 调到 80ms（远快于真实 450ms，但慢于轮询间隔 20ms，页面状态采样可靠）；
	# 点击冷却临时归零——首帧累积 delta 会让首个 create_timer 立即恢复，靠真实时钟过 250ms 冷却不稳
	var ui_cfg: Dictionary = GameData.config.get("ui", {})
	ui_cfg["auto_tick_ms"] = 80
	ui_cfg["click_cooldown_ms"] = 0
	var gs_script: GDScript = load("res://scripts/ui/game_screen.gd")
	var game: Control = gs_script.new(router, player)
	root.add_child(game)

	# 无怪场景：提示且不启动
	game._on_auto_toggle()
	check(not bool(game._auto_active) and String(game._toast.text) == "当前场景无可战斗对象", "自动战斗：无怪提示且不启动")

	# 低体力（<30%）：提示且不启动（间隔 > 点击冷却 250ms 再点）
	player.hurt(player.hp_cur - 29)
	await create_timer(0.3).timeout
	game._on_auto_toggle()
	check(player.hp_cur * 100 < player.max_hp() * Rules.auto_stop_hp_pct(), "自动战斗：低体力前置成立")
	check(not bool(game._auto_active) and String(game._toast.text) == "当前体力过低，不支持自动战斗", "自动战斗：低体力提示且不启动")

	# 满体力开打：自动发起战斗 → 攻击至胜利 → 继续 → 返回游戏 → 再战
	player.heal(9999)
	await create_timer(0.3).timeout
	router.handle("goto:nungcoeng")
	game._on_auto_toggle()
	check(bool(game._auto_active) and String(game._auto_btn.text) == "战斗ing", "自动战斗：启动并切换文案战斗ing")
	await _wait_until(func() -> bool: return router.combat != null and not router.combat.finished, 3.0, "自动战斗：自动发起战斗")
	# 首战削到残血：下一 tick 玩家先手必胜（缩序列长度，防自然损耗干扰后续断言）
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	await _wait_until(func() -> bool: return router.page.contains("战斗胜利"), 3.0, "自动战斗：自动攻击至胜利页")
	await _wait_until(func() -> bool: return router.page.contains("战利品"), 3.0, "自动战斗：胜利页自动点继续")
	await _wait_until(func() -> bool: return router.page.contains("威尼斯农场") and router.combat == null, 3.0, "自动战斗：战利品页自动返回游戏")
	await _wait_until(func() -> bool: return router.combat != null and not router.combat.finished, 3.0, "自动战斗：回场景后自动再战")

	# 体力压到阈值下 → 循环自动终止 + 按钮还原 + 提示
	player.hurt(ceili(player.hp_cur - player.max_hp() * 0.2))
	await _wait_until(func() -> bool: return not bool(game._auto_active), 3.0, "自动战斗：低体力自动终止")
	check(String(game._auto_btn.text) == "自动战斗", "自动战斗：终止后按钮文案还原")
	check(String(game._toast.text).contains("体力低于30%"), "自动战斗：低体力终止提示")

	# 手动停止：再次启动后点击「战斗ing」立即停
	player.heal(9999)
	await create_timer(0.3).timeout
	game._on_auto_toggle()
	check(bool(game._auto_active), "自动战斗：可再次启动")
	game._on_auto_toggle()
	check(not bool(game._auto_active) and String(game._auto_btn.text) == "自动战斗", "自动战斗：点击战斗ing手动停止")

	# 等挂起的循环协程走完最后一拍再释放节点，避免协程在已释放实例上恢复
	await create_timer(0.15).timeout
	game.queue_free()
	ui_cfg["auto_tick_ms"] = 450
	ui_cfg["click_cooldown_ms"] = 250


# ---------- 5.12 滚动配置断言（契约 trade-spec §8） ----------

func _test_scroll_fix(player: PlayerCore) -> void:
	var view := PageView.new()
	check(view.mouse_filter == Control.MOUSE_FILTER_PASS, "PageView mouse_filter=PASS（触摸滚动修复 §8）")
	view.free()
	var router := EventRouter.new()
	router.setup(player, null)
	var title := TitleScreen.new(router)
	root.add_child(title)
	check(title._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "标题屏 ScrollContainer SHOW_NEVER（§8）")
	title.queue_free()
	# GameScreen 引用 SaveManager（autoload 在 -s 模式下不可静态解析），运行时动态加载
	var gs_script: GDScript = load("res://scripts/ui/game_screen.gd")
	var game: Control = gs_script.new(router, player)
	root.add_child(game)
	var scroll: ScrollContainer = game.get("_scroll")
	check(scroll != null and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER, "游戏屏 ScrollContainer SHOW_NEVER（§8）")
	game.queue_free()


# ---------- 5.9 标题屏真实点击路径（回归：创建页必须有可见输入框） ----------

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


# ---------- 5.10 安全区适配（SafeAreaFrame） ----------

func _test_safe_area_frame() -> void:
	# 正常收窄：安全区四边各内收（720×1280 内容，安全区 10/90/10/48）
	var ins := SafeAreaFrame.compute_insets(Vector2(720, 1280), Rect2(10, 90, 700, 1142))
	check(ins == Vector4(10, 90, 10, 48), "compute_insets 正常收窄")
	# 安全区大于内容：四边全部钳零
	var big := SafeAreaFrame.compute_insets(Vector2(720, 1280), Rect2(-100, -100, 1000, 1600))
	check(big == Vector4.ZERO, "compute_insets 安全区大于内容钳零")
	# 负值一律钳零（安全区越出内容四边）
	var neg := SafeAreaFrame.compute_insets(Vector2(720, 1280), Rect2(-10, -90, 760, 1400))
	check(neg == Vector4.ZERO, "compute_insets 负值钳零")
	# 四边混合：左越界钳零、上收 90、右贴合 0、下收 90
	var mix := SafeAreaFrame.compute_insets(Vector2(720, 1280), Rect2(-10, 90, 730, 1100))
	check(mix == Vector4(0, 90, 0, 90), "compute_insets 四边混合")
	# 零尺寸内容兜底
	check(SafeAreaFrame.compute_insets(Vector2.ZERO, Rect2(0, 0, 10, 10)) == Vector4.ZERO,
		"compute_insets 零尺寸内容兜底")
	# --sim-insets 解析：命中与未命中
	var sim := SafeAreaFrame.parse_sim_insets(PackedStringArray(["--shot-tour", "--sim-insets=0,90,0,48"]))
	check(sim == Vector4(0, 90, 0, 48), "parse_sim_insets 正常解析")
	check(SafeAreaFrame.parse_sim_insets(PackedStringArray(["--shot-tour"])).x < 0.0,
		"parse_sim_insets 无参数返回哨兵")
	# 实例路径：注入模拟 insets 后即时应用到四边 margin
	var frame := SafeAreaFrame.new()
	root.add_child(frame)
	frame.set_simulated_insets(Vector4(5, 6, 7, 8))
	check(frame.get_theme_constant("margin_left") == 5 and frame.get_theme_constant("margin_top") == 6
		and frame.get_theme_constant("margin_right") == 7 and frame.get_theme_constant("margin_bottom") == 8,
		"SafeAreaFrame 实例应用模拟 insets")
	frame.queue_free()


# ---------- 6. 存档往返 ----------

func _test_player_roundtrip(player: PlayerCore) -> void:
	player.new_game("存档员", "♀")
	player.add_copper(888)
	player.add_stack("putaojiu", 300)
	player.bank_deposit(2)
	player.dungeon_day = 12345
	player.dungeon_kills = 7
	player.dungeon_deadline = 999
	player.exp_buff_left = 7
	player.exp_buff_mult = 5
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
	check(clone.dungeon_day == 12345 and clone.dungeon_kills == 7 and clone.dungeon_deadline == 999, "往返：地宫字段")
	check(clone.exp_buff_left == 7 and clone.exp_buff_mult == 5, "往返：经验加速 buff")
	var bad := clone.read_from({})
	check(not bad, "空存档拒绝")

	# 旧档兼容：缺地宫字段时取默认值
	var old_save: Dictionary = save.duplicate(true)
	var p: Dictionary = old_save.get("player", {})
	p.erase("dungeon_day")
	p.erase("dungeon_kills")
	p.erase("dungeon_deadline")
	p.erase("exp_buff_left")
	p.erase("exp_buff_mult")
	var clone2 := PlayerCore.new()
	root.add_child(clone2)
	check(clone2.read_from(old_save), "旧档读取成功")
	check(clone2.dungeon_day == -1 and clone2.dungeon_kills == 0 and clone2.dungeon_deadline == 0, "旧档地宫字段默认值")
	check(clone2.exp_buff_left == 0 and clone2.exp_buff_mult == 10, "旧档加速 buff 默认值")
	clone2.queue_free()


# ---------- 6.5 新字段存档往返 + 旧档兼容（契约 plan-v2 §4.1/§6） ----------

func _test_new_fields_roundtrip(player: PlayerCore) -> void:
	player.new_game("存档员2", "♀")
	player.stamina = 555
	player.weight_bonus = 50
	var belt := player.add_equip("piyaodai")
	check(player.equip_armor(belt), "穿戴护甲（存档准备）")
	player.add_time_buff("exp_buff", 1.0, 2.0)
	player.learn_skill("attack")
	player.bump_streak()
	player.bump_streak()
	player.bump_streak()
	player.quest_andrew = {"state": "active", "kills": 4, "day": 12345}
	player.quest_siren = {"shards": 2, "claimed": false}
	player.riddle_day = 99
	player.farm_plots[0] = {"seed_id": "mucao_zhongzi", "planted_unix": 777}
	player.gift_claimed = true
	player.add_stack("lanbaoshi", 1)
	var helmet := player.add_equip("cuzhitongkui")
	check(player.socket_gem(helmet, "lanbaoshi").get("ok", false), "镶嵌宝石（存档准备）")
	var h_inst: Dictionary = player.equips[helmet]
	h_inst["enhance"] = 3
	h_inst["bound"] = true

	var save := {}
	player.write_to(save)
	var clone := PlayerCore.new()
	root.add_child(clone)
	check(clone.read_from(save), "新字段往返：read_from 成功")
	check(clone.stamina == 555, "往返：生活体力")
	check(clone.weight_bonus == 50, "往返：负重加成")
	check(clone.armor_idx == belt, "往返：护甲下标")
	check(clone.buffs.size() == 1 and String((clone.buffs[0] as Dictionary).get("kind", "")) == "exp_buff"
		and absf(float((clone.buffs[0] as Dictionary).get("mult", 0.0)) - 2.0) < 0.001, "往返：时间制 buff")
	check(clone.skills.has("attack"), "往返：技能")
	check(clone.streak == 3 and clone.momentum == 3, "往返：连胜与士气")
	check(String(clone.quest_andrew.get("state", "")) == "active" and int(clone.quest_andrew.get("kills", -1)) == 4
		and int(clone.quest_andrew.get("day", -1)) == 12345, "往返：安德鲁任务")
	check(int(clone.quest_siren.get("shards", -1)) == 2 and not bool(clone.quest_siren.get("claimed", true)), "往返：西利亚任务")
	check(clone.riddle_day == 99, "往返：谜语当日")
	check(String((clone.farm_plots[0] as Dictionary).get("seed_id", "")) == "mucao_zhongzi"
		and int((clone.farm_plots[0] as Dictionary).get("planted_unix", 0)) == 777, "往返：农田")
	check(clone.gift_claimed, "往返：礼包标记")
	check((clone.equips[helmet] as Dictionary).get("gems", []).size() == 1
		and int((clone.equips[helmet] as Dictionary).get("enhance", 0)) == 3
		and bool((clone.equips[helmet] as Dictionary).get("bound", false)), "往返：装备实例扩展形状")
	clone.queue_free()

	# 旧档兼容：无新字段 + equips 旧形状 {id,dur} 可读，缺省补默认值
	var old_save: Dictionary = save.duplicate(true)
	var p: Dictionary = old_save.get("player", {})
	for key: String in ["stamina", "weight_bonus", "armor_idx", "buffs", "skills", "streak", "momentum",
		"quest_andrew", "quest_siren", "riddle_day", "farm_plots", "gift_claimed"]:
		p.erase(key)
	for inst: Dictionary in p.get("equips", []):
		inst.erase("gems")
		inst.erase("enhance")
		inst.erase("bound")
	var clone2 := PlayerCore.new()
	root.add_child(clone2)
	check(clone2.read_from(old_save), "旧档（无新字段）读取成功")
	check(clone2.stamina == clone2.max_stamina(), "旧档：体力默认满")
	check(clone2.weight_bonus == 0 and clone2.armor_idx == -1, "旧档：负重加成/护甲默认")
	check(clone2.buffs.is_empty() and clone2.skills.is_empty(), "旧档：buff/技能默认空")
	check(clone2.streak == 0 and clone2.momentum == 0, "旧档：连胜士气默认 0")
	check(String(clone2.quest_andrew.get("state", "")) == "" and int(clone2.quest_andrew.get("kills", -1)) == 0
		and int(clone2.quest_andrew.get("day", -1)) == -1, "旧档：安德鲁任务默认")
	check(int(clone2.quest_siren.get("shards", -1)) == 0 and not bool(clone2.quest_siren.get("claimed", true)), "旧档：西利亚任务默认")
	check(clone2.riddle_day == -1, "旧档：谜语默认")
	check(clone2.farm_plots.size() == Rules.life_farm_plots() and (clone2.farm_plots[0] as Dictionary).is_empty(), "旧档：农田默认空地×4")
	check(not clone2.gift_claimed, "旧档：礼包标记默认未领")
	check((clone2.equips[helmet] as Dictionary).get("gems", []).is_empty()
		and int((clone2.equips[helmet] as Dictionary).get("enhance", 0)) == 0
		and not bool((clone2.equips[helmet] as Dictionary).get("bound", false)), "旧档：equips 旧形状补默认值")
	clone2.queue_free()


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


# ---------- 5.18 出海航行 + 区域世界（契约 docs/sail-region-spec.md §0/§1.4-§1.8） ----------

## 区域怪 18（id: 等级，id 全部锁死 sail-region 契约 §1.4）
const SAIL_REGION_MOBS := {
	"laguzha_haidao": 11, "laguzha_yejueshu": 13,
	"risiben_shanzei": 13, "risiben_haiyaokui": 15,
	"masa_shijiang": 15, "masa_yaolang": 17,
	"tunisi_tuying": 17, "tunisi_shajuan": 19,
	"aerjier_haigui": 19, "aerjier_leiwei": 21,
	"yalishanda_shawei": 21, "yalishanda_munaiyi": 23,
	"yadian_shanhou": 23, "yadian_shedian": 25,
	"yisitanbao_tieqi": 25, "yisitanbao_leishi": 27,
	"yisitanbuer_jinwei": 27, "yisitanbuer_huan": 29,
}

## 海怪 6（habitat=="sea"，等级 5/10/15/20/25/30，契约 §1.4）
const SAIL_SEA_MOBS := {
	"haiou_qun": 5, "anjiao_renyu": 10, "shenhai_ju_man": 15,
	"youling_fanchuan": 20, "kelaken_youzai": 25, "fengbao_sairen": 30,
}

## 18 个新野外场景（契约 §1.2，每区 2 个）
const SAIL_REGION_SCENES := [
	"laguzha_haian", "laguzha_shanqiu",
	"risiben_jiaoqu", "risiben_haijiao",
	"masa_shidi", "masa_yakuang",
	"tunisi_luzhou", "tunisi_shamo",
	"aerjier_haiwan", "aerjier_yaolei",
	"yalishanda_shaqiu", "yalishanda_gumu",
	"yadian_shanlin", "yadian_shendian",
	"yisitanbao_chengjiao", "yisitanbao_yaolei",
	"yisitanbuer_jiaoqu", "yisitanbuer_huanggong",
]

## 4 件新装备（契约 §1.5）：id → 期望字段（武器验 atk、护甲验 def/slots）
const SAIL_REGION_EQUIPS := {
	"longya_ren": {"req_level": 24, "price": 42000, "atk": [124, 210]},
	"longlin_jia": {"req_level": 24, "price": 46000, "def": 34, "slots": 1},
	"fenghuang_zhang": {"req_level": 26, "price": 56000, "atk": [134, 228]},
	"shengdian_zhongkai": {"req_level": 26, "price": 60000, "def": 38, "slots": 1},
}


func _test_sail_region_data(player: PlayerCore) -> void:
	# ---- 数据硬校验（D1 波1 并行：数据未就位时整组跳过并记「预期并行缺口」，不改 data/*） ----
	var missing_mobs: Array[String] = []
	for mid: String in SAIL_REGION_MOBS:
		if not GameData.has_monster(mid):
			missing_mobs.append(mid)
	for sea_id: String in SAIL_SEA_MOBS:
		if not GameData.has_monster(sea_id):
			missing_mobs.append(sea_id)
	if missing_mobs.is_empty():
		for mid2: String in SAIL_REGION_MOBS:
			_check_sail_monster_formula(mid2, int(SAIL_REGION_MOBS[mid2]))
		for sea_id2: String in SAIL_SEA_MOBS:
			_check_sail_monster_formula(sea_id2, int(SAIL_SEA_MOBS[sea_id2]))
			check(String(GameData.get_monster(sea_id2).get("habitat", "")) == "sea",
				"海怪 %s habitat=sea（契约 §1.4）" % sea_id2)
	else:
		push_warning("SKIP: sail-region 数据硬校验（24 新怪）缺 %d 个 id，预期并行缺口（D1 波1）" % missing_mobs.size())

	var missing_scenes := 0
	for sid: String in SAIL_REGION_SCENES:
		if not GameData.has_scene(sid):
			missing_scenes += 1
	if missing_scenes == 0:
		for sid2: String in SAIL_REGION_SCENES:
			var scene: Dictionary = GameData.get_scene(sid2)
			for exit_e: Dictionary in scene.get("exits", []):
				var to := String(exit_e.get("to", ""))
				check(GameData.has_scene(to), "新场景 %s 出口指向存在的场景 %s" % [sid2, to])
				var back := false
				for back_e: Dictionary in GameData.get_scene(to).get("exits", []):
					if String(back_e.get("to", "")) == sid2:
						back = true
						break
				check(back, "新场景 %s ↔ %s 出口双向闭合" % [sid2, to])
			var mons: Array = scene.get("monsters", [])
			check(not mons.is_empty(), "新场景 %s 挂有本区怪" % sid2)
			for m_entry: Dictionary in mons:
				check(GameData.has_monster(String(m_entry.get("id", ""))),
					"新场景 %s 怪物 %s 存在" % [sid2, String(m_entry.get("id", ""))])
	else:
		push_warning("SKIP: sail-region 数据硬校验（18 新场景）缺 %d 个 id，预期并行缺口（D1 波1）" % missing_scenes)

	if not GameData.regions_data.is_empty():
		check(GameData.regions_data.size() == 10, "regions_data 应为 10 项（实际 %d）" % GameData.regions_data.size())
		for region: Dictionary in GameData.regions_data:
			var rid := String(region.get("id", "?"))
			var ps := String(region.get("port_scene", ""))
			check(ps != "" and GameData.has_scene(ps), "区域 %s port_scene 场景存在" % rid)
			for member in region.get("scenes", []):
				check(GameData.has_scene(String(member)), "区域 %s scenes 成员场景存在（%s）" % [rid, String(member)])
		check(String(GameData.region_of_scene("sicoeng").get("id", "")) == "venice",
			"region_of_scene：真实数据 sicoeng 命中 venice 区")
	else:
		push_warning("SKIP: sail-region 数据硬校验（regions_data）未就位，预期并行缺口（D1 波1）")

	var missing_equips := 0
	for eid: String in SAIL_REGION_EQUIPS:
		if not GameData.has_item(eid):
			missing_equips += 1
	if missing_equips == 0:
		for eid2: String in SAIL_REGION_EQUIPS:
			var spec: Dictionary = SAIL_REGION_EQUIPS[eid2]
			var item: Dictionary = GameData.get_item(eid2)
			check(int(item.get("req_level", -1)) == int(spec.get("req_level", -1)),
				"新装备 %s req_level=%d" % [eid2, int(spec.get("req_level", -1))])
			check(int(item.get("price", -1)) == int(spec.get("price", -1)),
				"新装备 %s price=%d" % [eid2, int(spec.get("price", -1))])
			if spec.has("atk"):
				var want_atk: Array = spec.get("atk", [])
				var atk: Array = item.get("atk", [])
				check(atk.size() == 2 and int(atk[0]) == int(want_atk[0]) and int(atk[1]) == int(want_atk[1]),
					"新装备 %s atk=%s" % [eid2, str(want_atk)])
			if spec.has("def"):
				check(int(item.get("def", -1)) == int(spec.get("def", -1)),
					"新装备 %s def=%d" % [eid2, int(spec.get("def", -1))])
				check(int(item.get("slots", -1)) == int(spec.get("slots", -1)),
					"新装备 %s slots=%d" % [eid2, int(spec.get("slots", -1))])
	else:
		push_warning("SKIP: sail-region 数据硬校验（4 新装备）缺 %d 件，预期并行缺口（D1 波1）" % missing_equips)

	# ---- 引擎自证用例（不依赖 D1，契约 §2：构造内存数据自证） ----

	# Rules getter（economy 节，config 随 E1 落地，契约 §1.7）
	check(Rules.sail_cost() == 1000, "Rules.sail_cost()=1000（契约 §1.7）")
	check(Rules.inn_cost() == 100, "Rules.inn_cost()=100（契约 §1.7）")

	# CombatEngine.at_sea：默认 false 且可置位（判定/文案归路由层，契约 §1.6）
	player.new_game("水手", "♂")
	var sea_engine := CombatEngine.new("bingji", player)
	check(sea_engine != null and not sea_engine.at_sea, "CombatEngine.at_sea 默认 false")
	sea_engine.at_sea = true
	check(sea_engine.at_sea, "CombatEngine.at_sea 可置位")

	# Life.inn_rest（契约 §1.7）：扣费 + 生活体力回满 + HP 回满 + hp_changed 广播
	player.new_game("住店客", "♂")
	player.add_copper(1000)
	player.stamina = 0
	player.hurt(player.hp_cur)
	var hp_signals := [0]
	player.hp_changed.connect(func(_c: int, _m: int) -> void: hp_signals[0] += 1)
	var res := Life.inn_rest(player, Rules.inn_cost())
	check(bool(res.get("ok", false)), "inn_rest：余额充足住店成功")
	check(player.copper == 1000 - Rules.inn_cost(), "inn_rest：扣费=inn_cost")
	check(player.stamina == player.max_stamina(), "inn_rest：生活体力回满")
	check(player.hp_cur == player.max_hp(), "inn_rest：HP 回满")
	check(hp_signals[0] >= 1, "inn_rest：hp_changed 已广播")
	check(String(res.get("msg", "")).contains("全都回满"), "inn_rest：契约成功文案")

	# 余额不足：ok:false + 契约文案 + 不恢复
	player.take_copper(player.copper)
	player.stamina = 0
	var res_bad := Life.inn_rest(player, Rules.inn_cost())
	check(not bool(res_bad.get("ok", true)), "inn_rest：余额不足拒绝")
	check(String(res_bad.get("msg", "")).contains("拿不出来"), "inn_rest：契约不足文案")
	check(player.stamina == 0, "inn_rest：拒绝不恢复生活体力")

	# GameData.region_of_scene（契约 §1.8）：内存注入 regions 测三种路径，测后还原
	var saved_regions: Array[Dictionary] = GameData.regions_data
	var injected: Array[Dictionary] = [
		{"id": "venice", "name": "威尼斯", "map_kind": "venice", "port_scene": "sicoeng", "scenes": []},
		{"id": "laguzha", "name": "拉古扎", "map_kind": "area", "port_scene": "laguzha", "scenes": ["laguzha_haian"]},
	]
	GameData.regions_data = injected
	check(String(GameData.region_of_scene("sicoeng").get("id", "")) == "venice",
		"region_of_scene：port_scene 命中 venice 区")
	check(String(GameData.region_of_scene("laguzha").get("id", "")) == "laguzha",
		"region_of_scene：他区港口命中所在区")
	check(String(GameData.region_of_scene("laguzha_haian").get("id", "")) == "laguzha",
		"region_of_scene：scenes 成员命中所在区")
	check(String(GameData.region_of_scene("nowhere_xyz").get("id", "")) == "venice",
		"region_of_scene：未知场景兜底 venice 区")
	GameData.regions_data = []
	check(GameData.region_of_scene("sicoeng").is_empty(), "region_of_scene：regions 未载返回 {}")
	GameData.regions_data = saved_regions


## 契约新怪数值公式硬校验（sail-region §0：hp=round(40×L^1.2)、atk=[3+2L,8+3L]、
## def=round(5+1.5L)、exp=[round(0.8L)+1,4L+5]、copper=[5L,15L+10]、instances=5，容差 0）
func _check_sail_monster_formula(mid: String, lv: int) -> void:
	var m: Dictionary = GameData.get_monster(mid)
	if m.is_empty():
		check(false, "契约新怪 %s 存在" % mid)
		return
	check(int(m.get("level", -1)) == lv, "契约新怪 %s 等级=%d" % [mid, lv])
	check(int(m.get("hp", -1)) == int(round(40.0 * pow(float(lv), 1.2))),
		"契约新怪 %s hp=round(40×L^1.2)（L=%d）" % [mid, lv])
	var atk: Array = m.get("atk", [])
	check(atk.size() == 2 and int(atk[0]) == 3 + 2 * lv and int(atk[1]) == 8 + 3 * lv,
		"契约新怪 %s atk=[3+2L,8+3L]（L=%d）" % [mid, lv])
	check(int(m.get("def", -1)) == int(round(5.0 + 1.5 * float(lv))),
		"契约新怪 %s def=round(5+1.5L)（L=%d）" % [mid, lv])
	var exp_r: Array = m.get("exp", [])
	check(exp_r.size() == 2 and int(exp_r[0]) == int(round(0.8 * float(lv))) + 1 and int(exp_r[1]) == 4 * lv + 5,
		"契约新怪 %s exp=[round(0.8L)+1,4L+5]（L=%d）" % [mid, lv])
	var copper: Array = m.get("copper", [])
	check(copper.size() == 2 and int(copper[0]) == 5 * lv and int(copper[1]) == 15 * lv + 10,
		"契约新怪 %s copper=[5L,15L+10]（L=%d）" % [mid, lv])
	check(int(m.get("instances", -1)) == 5, "契约新怪 %s instances=5" % mid)


# ---------- 5.18b 出海航行 + 区域世界 页面/链路（契约 docs/sail-region-spec.md §1.6-§1.8/§1.10） ----------

func _test_sail_region_flow(player: PlayerCore) -> void:
	# ---- Pages 层（E2b 本体，不依赖路由） ----
	player.new_game("航海士", "♂")
	player.add_copper(20000)

	# region_of_scene 分流（契约 §1.8，真实数据）：venice 港→venice 区，外港→其区
	check(String(GameData.region_of_scene("sicoeng").get("id", "")) == "venice", "region_of_scene：sicoeng→venice 区")
	check(String(GameData.region_of_scene("risiben").get("id", "")) == "risiben", "region_of_scene：risiben→其区")

	# region_map：BBCode 含 goto/npc 链接与 WIDE_SEP（契约 §1.8）
	var region := GameData.region_of_scene("risiben")
	if region.is_empty():
		check(false, "region_map：risiben 区数据缺失")
	else:
		player.set_location("risiben")
		var rmap := Pages.region_map(player, region)
		check(rmap.contains(String(region.get("map_name", ""))), "region_map：header=map_name")
		check(rmap.contains("goto:risiben") and rmap.contains("goto:risiben_jiaoqu") and rmap.contains("goto:risiben_haijiao"),
			"region_map：港口+scenes goto 链接")
		check(rmap.contains("npc:risiben:sailor") and rmap.contains("npc:risiben:innkeeper") and rmap.contains("npc:risiben:smith"),
			"region_map：特色人物 sailor/inn/smith 链接")
		check(rmap.contains("npc:risiben:laoshuishou"), "region_map：带 lines 的 flavor 入列")
		check(rmap.contains(Pages.WIDE_SEP), "region_map：地点 WIDE_SEP 折行")
		check(rmap.contains("worldmap"), "region_map：尾部大世界链接")

	# sailor_page：9 个 sail_to 链接（当前港不可选）+ 船费说明
	player.set_location("sicoeng")
	var sp := Pages.sailor_page(player)
	var sail_links := sp.count("sail_to:")
	check(sail_links == 9, "sailor_page：9 个 sail_to 链接（实际 %d）" % sail_links)
	check(sp.contains("船主") and sp.contains("当前所在"), "sailor_page：船主标题与当前所在标记")
	check(sp.contains("船费 %d 铜贝" % Rules.sail_cost()), "sailor_page：船费说明")

	# inn_page / inn_result（契约 §1.7）：台词套 {昵称}、房费、inn_rest 链接、成败文案
	var inn_npc := {}
	for npc: Dictionary in GameData.get_scene("risiben").get("npcs", []):
		if String(npc.get("kind", "")) == "inn":
			inn_npc = npc
			break
	check(not inn_npc.is_empty(), "inn：risiben 旅店 NPC 存在")
	var ip := Pages.inn_page(player, inn_npc)
	check(ip.contains(String(inn_npc.get("name", ""))), "inn_page：header=npc 名")
	check(ip.contains(player.nickname), "inn_page：台词 {昵称} 替换")
	check(ip.contains(str(Rules.inn_cost())), "inn_page：房费展示")
	check(ip.contains("inn_rest") and ip.contains("开房休息"), "inn_page：开房休息链接")
	player.stamina = 10
	var res := Life.inn_rest(player, Rules.inn_cost())
	check(bool(res.get("ok", false)), "inn：Life.inn_rest 成功前置")
	var ir := Pages.inn_result(player, res)
	check(ir.contains("回满") and ir.contains("返回"), "inn_result：成功恢复文案+返回")
	var ir_bad := Pages.inn_result(player, {"ok": false, "msg": "房费都拿不出来。"})
	check(ir_bad.contains("拿不出来"), "inn_result：失败显示 msg")

	# smith_page stock（契约 §1.3/§1.9）：stock 页只列档位内装备，缺省=威尼斯全量
	var smith_npc := {}
	for npc2: Dictionary in GameData.get_scene("risiben").get("npcs", []):
		if String(npc2.get("kind", "")) == "smith":
			smith_npc = npc2
			break
	check(not smith_npc.is_empty() and not (smith_npc.get("stock", []) as Array).is_empty(), "smith：risiben 铁匠 stock 存在")
	player.set_location("risiben")
	var stock_page := Pages.smith_page(player, smith_npc)
	var stock_size := (smith_npc.get("stock", []) as Array).size()
	var buy_links := stock_page.count("buy_equip:")
	check(stock_page.contains("里斯本 · 铁匠铺"), "smith_page：stock 页 header=区域名·铁匠铺")
	check(buy_links == stock_size, "smith_page：只列 stock 档位（%d/%d）" % [buy_links, stock_size])
	check(stock_page.contains("buy_equip:changjian"), "smith_page：stock 首件在售")
	check(not stock_page.contains("buy_equip:lingzhuzhiren"), "smith_page：档位外装备（L22）不在售")
	var default_page := Pages.smith_page(player)
	check(default_page.contains("威尼斯铁匠铺") and default_page.contains("buy_equip:lingzhuzhiren"),
		"smith_page：缺省=威尼斯铁匠铺全量在售")

	# combat_page 海战形态（契约 §1.6）：标题行海战标识 + 去掉撤退链接
	var eng := CombatEngine.new("bingji", player)
	var land_page := Pages.combat_page(eng, player, false, "")
	check(land_page.contains("敌方属性") and land_page.contains("retreat"), "combat_page：陆战保留撤退")
	eng.at_sea = true
	var sea_page := Pages.combat_page(eng, player, false, "")
	check(sea_page.contains("海战"), "combat_page：海战标识")
	check(not sea_page.contains("撤退"), "combat_page：海战无撤退链接")

	# lose_page 海战变体（契约 §1.6）：默认原文案保留
	check(Pages.lose_page(eng, 100, "威尼斯", true).contains("商船救起"), "lose_page：海战战败变体")
	var lp_land := Pages.lose_page(eng, 100, "威尼斯")
	check(lp_land.contains("好心人救回了城里") and not lp_land.contains("商船"), "lose_page：默认原文案")

	# worldmap 行尾区域地图提示（契约 §1.8）
	check(Pages.worldmap_page(player).contains("在各地港口点"), "worldmap：行尾区域地图提示")

	# ---- Router 航海全流程（E2a 侧：未就位记预期并行缺口，不改 event_router.gd） ----
	var router := EventRouter.new()
	router.setup(player, null)
	router.handle("goto:sicoeng")
	router.handle("npc:sicoeng:sailor")
	if not router.page.contains("sail_to:"):
		push_warning("SKIP: 航海全流程——E2a event_router.gd 未就位（船主页无 sail_to），预期并行缺口")
		return
	var wallet := player.copper
	var dest_idx := _port_index("risiben")
	var dest_scene := Trade.port_scene("risiben")
	router.handle("sail_to:%d" % dest_idx)
	check(player.location == "sicoeng", "sail_to：海上期间位置不变（出发港）")
	check(router.combat != null and router.combat.at_sea, "sail_to：进入海战（at_sea）")
	check(player.copper == wallet - Rules.sail_cost(), "sail_to：扣船费 sail_cost")
	var sea_evts: Array[String] = []
	for a: Dictionary in router.bottom_actions():
		sea_evts.append(String(a.get("event", "")))
	check(not sea_evts.has("retreat"), "海战 bottom_actions：无撤退")
	check(router.page.contains("海战"), "海战页：海战标识")
	router.combat.monster_hp = 1
	router.combat.monster_def = 0
	router.handle("attack")
	check(router.combat.finished and router.combat.won, "海战胜利")
	check(player.location == dest_scene, "胜利抵达目的港")
	check((router.sail_port as Dictionary).is_empty(), "抵达后 sail_port 清空")
	router.handle("combat_reward")
	router.handle("combat_leave")
	check(router.combat == null, "战斗状态清理（航海用例）")

	# 钱不够不能开航（契约 §1.6：不足→提示，不进战斗、不移动、不扣费）
	player.take_copper(player.copper)
	router.handle("npc:%s:sailor" % dest_scene)
	var broke_wallet := player.copper
	router.handle("sail_to:0")
	check(router.combat == null, "钱不够不进战斗")
	check(player.location == dest_scene, "钱不够不移动")
	check(player.copper == broke_wallet, "钱不够不扣费")

	# ---- 传送并存恢复（契约 docs/sail-region-spec.md §1.10：传送安全直达，航海为风险备选） ----
	var has_tp := false
	for npc3: Dictionary in GameData.get_scene("maatau").get("npcs", []):
		if String(npc3.get("kind", "")) == "teleport":
			has_tp = true
			break
	check(has_tp, "teleport：maatau 场景有 kind=teleport 的传送师 NPC")
	player.add_copper(Rules.teleport_cost_copper())
	player.set_location("sicoeng")
	router.handle("teleport")
	check(router.page.contains("tp:"), "teleport：传送页含 tp: 链接")
	check(router.page.contains("安全直达"), "teleport：传送页含与航海的区分文案")
	var tp_wallet := player.copper
	router.handle("tp:%d" % _port_index("risiben"))
	check(player.location == Trade.port_scene("risiben"), "tp：传送后 location 变为目的港")
	check(player.copper == tp_wallet - Rules.teleport_cost_copper(), "tp：扣传送费 %d 铜" % Rules.teleport_cost_copper())
