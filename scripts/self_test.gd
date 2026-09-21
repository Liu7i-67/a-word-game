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
	_test_update_checker(player)
	_test_trade_engine()
	_test_trade_router(player)
	_test_sell_equip(player)
	await _test_auto_battle(player)
	_test_drop_equip(player)
	_test_title_click_path(player)
	_test_scroll_fix(player)
	_test_safe_area_frame()
	_test_player_roundtrip(player)
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

	var npc_kinds := ["flavor", "welfare", "church", "bank", "casino", "market", "teleport", "sail", "dungeon", "shop", "smith", "dungeon_keeper", "trade_market", "tavern_rumor"]
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
			var atk: Array = def.get("atk", [])
			check(atk.size() == 2 and int(atk[1]) >= int(atk[0]), "装备 %s 攻击区间非法" % iid)
		if String(def.get("type", "")) == "drug":
			check(int(def.get("heal", 0)) > 0 or def.has("exp_buff"), "药品 %s 缺 heal/exp_buff" % iid)
			check(def.has("exp_buff") or int(def.get("price", 0)) > 0, "药品 %s 缺 price" % iid)
		var forge: Dictionary = def.get("forge", {})
		if not forge.is_empty():
			var mats: Dictionary = forge.get("materials", {})
			check(not mats.is_empty() and int(forge.get("copper", 0)) > 0, "装备 %s forge 配置非法" % iid)
			for mid: String in mats:
				check(GameData.items.has(mid), "装备 %s 打造材料 %s 不存在" % [iid, mid])


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

	# 状态 / 地图 / 传送
	router.handle("status")
	check(router.page.contains("昵称：马可波罗"), "状态页")
	router.handle("map")
	check(router.page.contains("威尼斯城内地图"), "城内地图")
	router.handle("goto:maatau")
	router.handle("npc:maatau:teleporter")
	check(router.page.contains("地中海"), "传送页")
	if GameData.world_ports.is_empty():
		router.handle("tp:1")
		check(router.page.contains("暂未开发区域"), "未开放港口占位（原文案）")
	else:
		# world 就位：tp 真实出海（契约 trade-spec §6），验完回威尼斯继续旧链路
		var wallet0 := player.copper + player.bank_silver * Rules.copper_per_silver()
		router.handle("tp:1")
		check(player.location == String(GameData.world_ports[1].get("scene", "")), "tp 到达目标港场景")
		check(router.page.contains("船票花去"), "船票提示页")
		check(player.copper + player.bank_silver * Rules.copper_per_silver() == wallet0 - Rules.teleport_cost_copper(), "tp 扣费 1000 铜贝")
		router.handle("goto:maatau")
	router.handle("npc:maatau:sailor")
	check(router.page.contains("暂未开发区域"), "出航占位（原文案）")
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
	check(player.count_stack(pill_id) == pill0 + 3, "正确密码加速丹×3 入包")
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
	check(player.count_stack(pill_id) == pill0 + 6, "彩蛋可重复触发（丹再+3）")
	check(player.equips.size() == eq0 + 2, "彩蛋可重复触发（小刀再+1）")

	# 加速丹：药品页展示 + 使用 → 10 场 ×10
	player.equip_hand(player.equips.size() - 1)
	router.handle("items:drug")
	check(router.page.contains("经验×10（10场）"), "药品页显示加速丹效果")
	router.handle("use_drug:%s" % pill_id)
	check(player.exp_buff_left == 10 and player.exp_buff_mult == 10, "服丹后 10 场 ×10")
	check(player.count_stack(pill_id) == pill0 + 5, "服丹数量 -1")
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
	check(player.exp_buff_left == 10, "战斗中服丹重新激活至 10 场")
	check(player.count_stack(pill_id) == pill0 + 4, "战斗中服丹数量 -1")
	check(player.hp_cur == hp_before, "战斗中服丹怪物不还手")
	player.add_copper(1000)
	router.handle("retreat")
	check(router.combat == null, "战斗用丹用例撤退清理")


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


# ---------- 5.10 航海贸易链路（契约 §4-§6：跨港买卖/情报真实性/tp 扣费） ----------

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

	# tp 去产地港（页面写 10 银，实扣 cost_copper=1000 铜贝，银行自动折兑）
	router.handle("tp:%d" % _port_index(origin))
	check(player.location == Trade.port_scene(origin), "tp 到达产地港")
	wallet -= Rules.teleport_cost_copper()
	check(player.copper + player.bank_silver * Rules.copper_per_silver() == wallet, "tp 实扣 teleport.cost_copper")
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
	# 港口传送页（当前所在标记）→ tp 去热门港
	router.handle("npc:%s:teleporter" % Trade.port_scene(origin))
	check(router.page.contains("当前所在"), "传送页标当前所在")
	router.handle("tp:%d" % _port_index(dest))
	check(player.location == Trade.port_scene(dest), "tp 到达热门港")
	wallet -= Rules.teleport_cost_copper()
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
	check(player.copper + player.bank_silver * Rules.copper_per_silver() == wallet, "链路终钱包对账")
	# tp 钱不够：船老板语气提示，位置不变
	player.bank_withdraw(player.bank_silver)
	player.take_copper(player.copper)
	var loc0 := player.location
	router.handle("tp:0")
	check(player.location == loc0, "钱不够不移动")
	check(router.page.contains("船老板"), "钱不够给船老板语气提示")


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
		if not (ids.has("merchant") and ids.has("barkeep") and ids.has("teleporter")):
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
