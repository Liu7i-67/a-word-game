class_name Pages
## 页面构建器：把游戏状态渲染成 BBCode「页面」（对应原版的场景 HTML）。
## 页面内可点击元素一律 [url=事件]文案[/url]，事件由 EventRouter 分发。
## 橙色标题/蓝色链接致敬原版内嵌 CSS（h2 #ff9900、a blue）。

const HEADER_COLOR := "#ff9900"
const DIM_COLOR := "#9a9a9a"
const SEP := " . "


static func esc(s: String) -> String:
	# 先换占位符再还原：防止插入的 [lb]/[rb] 自身被二次替换（标签含 [] 时）
	return s.replace("[", "\u0001").replace("]", "\u0002").replace("\u0001", "[lb]").replace("\u0002", "[rb]")


static func link(event: String, label: String) -> String:
	return "[color=%s][url=%s]%s[/url][/color]" % [Rules.link_color(), event, esc(label)]


static func header(text: String) -> String:
	return "[b][color=%s]%s[/color][/b]" % [HEADER_COLOR, esc(text)]


static func dim(text: String) -> String:
	return "[color=%s]%s[/color]" % [DIM_COLOR, esc(text)]


## 通用页脚导航（对应原版通用 event：状态/物品/返回游戏 + 城内地图）
static func footer() -> String:
	return "%s %s %s %s %s %s %s" % [
		link("status", "状态"), SEP,
		link("items", "物品"), SEP,
		link("map", "地图"), SEP,
		link("back_game", "返回游戏"),
	]


# ---------- 开场与角色创建 ----------

static func intro_title(has_save: bool) -> String:
	var t := story_title()
	var title := String(t.get("name", "縱橫四海"))
	var tagline := String(t.get("tagline", ""))
	var start_link := String(t.get("link", "启动冒险之旅"))
	var lines: Array[String] = []
	lines.append("[center][b][font_size=72]%s[/font_size][/b][/center]" % esc(title))
	lines.append("")
	lines.append("[center]%s[/center]" % esc(tagline))
	lines.append("")
	lines.append("[center]%s[/center]" % link("story:0", start_link))
	if has_save:
		lines.append("[center]%s[/center]" % link("continue", "继续冒险"))
	return join_lines(lines)


static func story_title() -> Dictionary:
	return GameData.story.get("title", {})


static func story_pages() -> Array:
	return GameData.story.get("pages", [])


static func intro_page(idx: int) -> String:
	var pages := story_pages()
	if idx < 0 or idx >= pages.size():
		return create_page("")
	var page: Dictionary = pages[idx]
	var next_idx := idx + 1
	var next_event := "story:%d" % next_idx if next_idx < pages.size() else "story:99"
	var lines: Array[String] = []
	lines.append("[font_size=26]%s[/font_size]" % esc(String(page.get("text", ""))))
	lines.append("")
	lines.append("[center]%s[/center]" % link(next_event, String(page.get("link", "继续"))))
	return join_lines(lines)


static func create_page(error_msg: String) -> String:
	var lines: Array[String] = []
	lines.append(header("角色创建"))
	lines.append("请在上方输入框中输入角色名（12 字以内），然后点击注册男 / 注册女。")
	lines.append("")
	lines.append("[center]%s %s %s[/center]" % [link("create:♂", "注册男"), SEP, link("create:♀", "注册女")])
	if error_msg != "":
		lines.append("")
		lines.append("[color=red]%s[/color]" % esc(error_msg))
	return join_lines(lines)


# ---------- 场景页 ----------

static func scene_page(player: PlayerCore, scene_id: String) -> String:
	var scene := GameData.get_scene(scene_id)
	if scene.is_empty():
		return notice_page("四周雾气茫茫，你迷路了……", "goto:zaugun", "回到酒馆")
	var lines: Array[String] = []
	lines.append(header(String(scene.get("name", ""))))
	lines.append(esc(String(scene.get("desc", ""))))
	var monsters: Array = scene.get("monsters", [])
	if not monsters.is_empty():
		lines.append("")
		lines.append(header("出没"))
		var parts: Array[String] = []
		for m: Dictionary in monsters:
			var monster := GameData.get_monster(String(m.get("id", "")))
			var count := maxi(int(m.get("count", 1)), 1)
			for i in count:
				parts.append(link("fight:%s" % String(m.get("id", "")), String(monster.get("name", "???"))))
		lines.append(SEP.join(PackedStringArray(parts)))
	var npcs: Array = scene.get("npcs", [])
	if not npcs.is_empty():
		lines.append("")
		lines.append(header("人物"))
		var parts: Array[String] = []
		for npc: Dictionary in npcs:
			parts.append(link("npc:%s:%s" % [String(scene.get("id", "")), String(npc.get("id", ""))], String(npc.get("name", ""))))
		lines.append(SEP.join(PackedStringArray(parts)))
	var exits: Array = scene.get("exits", [])
	if not exits.is_empty():
		lines.append("")
		lines.append(header("出口"))
		lines.append(exits_block(exits))
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


static func exits_block(exits: Array) -> String:
	var by_dir := {}
	var dir_order: Array[String] = []
	for e: Dictionary in exits:
		var dir := String(e.get("dir", ""))
		if not by_dir.has(dir):
			by_dir[dir] = []
			dir_order.append(dir)
		by_dir[dir].append(e)
	var lines: Array[String] = []
	for dir in dir_order:
		var parts: Array[String] = []
		for e: Dictionary in by_dir[dir]:
			if bool(e.get("locked", false)):
				parts.append("%s（暂未开放）" % esc(String(e.get("name", ""))))
			else:
				var target := GameData.get_scene(String(e.get("to", "")))
				var label := String(target.get("short", ""))
				if label == "":
					label = String(target.get("name", ""))
				parts.append(link("goto:%s" % String(e.get("to", "")), label))
		lines.append("[b]%s:[/b] %s" % [esc(dir), SEP.join(PackedStringArray(parts))])
	return join_lines(lines)


# ---------- 状态 / 物品 / 装备 ----------

static func status_page(player: PlayerCore) -> String:
	var atk := player.atk_range()
	var hand := player.hand_item()
	var hand_name := "空手" if hand.is_empty() else player.item_name(String(hand.get("id", "")))
	var lines: Array[String] = []
	lines.append(header("状态"))
	lines.append("昵称：%s" % esc(player.nickname))
	lines.append("性别：%s" % player.gender)
	lines.append("等级：%d" % player.level)
	lines.append("经验：%d/%d" % [player.exp_cur, player.exp_need()])
	lines.append("体力：%d/%d" % [player.hp_cur, player.max_hp()])
	lines.append("攻击：%d-%d" % [atk.x, atk.y])
	lines.append("防御：%d" % player.defense())
	lines.append("装备：%s" % esc(hand_name))
	lines.append("负重：%d/%d" % [player.weight(), player.weight_cap()])
	lines.append("铜贝：%d  金贝：%d  银行存款：%d银贝" % [player.copper, player.gold, player.bank_silver])
	lines.append("罪恶：%d" % player.sin)
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


const ITEM_CATS := {"equip": "装备", "gem": "宝石", "drug": "药品", "other": "其他"}


static func items_page(player: PlayerCore, cat: String) -> String:
	if not ITEM_CATS.has(cat):
		cat = "equip"
	var lines: Array[String] = []
	lines.append(header("物品"))
	var tabs: Array[String] = []
	for key: String in ITEM_CATS:
		if key == cat:
			tabs.append("[b]【%s】[/b]" % ITEM_CATS[key])
		else:
			tabs.append(link("items:%s" % key, "【%s】" % ITEM_CATS[key]))
	lines.append(SEP.join(PackedStringArray(tabs)))
	lines.append("体力：%d  负重：%d/%d" % [player.hp_cur, player.weight(), player.weight_cap()])
	lines.append("贝钱：%d  金贝：%d" % [player.copper, player.gold])
	lines.append("")
	match cat:
		"equip":
			if player.equips.is_empty():
				lines.append(dim("暂无装备。"))
			for i in player.equips.size():
				var inst := player.equips[i]
				var def := GameData.get_item(String(inst.get("id", "")))
				var max_dur := maxi(int(def.get("durability", 1)), 1)
				var marker := "（手持）" if i == player.hand else ""
				var label := "%s%s 耐久%d/%d" % [player.item_name(String(inst.get("id", ""))), marker, int(inst.get("dur", 0)), max_dur]
				lines.append(link("equip_view:%d" % i, label))
		"other":
			var any := false
			for id: String in player.bag:
				var def := GameData.get_item(id)
				if String(def.get("type", "")) == "goods":
					any = true
					lines.append("%s ×%d" % [esc(String(def.get("name", id))), int(player.bag[id])])
			if not any:
				lines.append(dim("暂无杂物。可以去市场买些本地特产。"))
		"gem":
			lines.append(dim("暂无宝石。"))
		"drug":
			var any_drug := false
			for id: String in player.bag:
				var def := GameData.get_item(id)
				if String(def.get("type", "")) != "drug":
					continue
				any_drug = true
				lines.append("%s ×%d 疗效+%d  %s" % [
					esc(String(def.get("name", id))), int(player.bag[id]), int(def.get("heal", 0)),
					link("use_drug:%s" % id, "[使用]"),
				])
			if not any_drug:
				lines.append(dim("暂无药品。神父的免费治疗倒是一直都在。"))
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


static func equip_detail(player: PlayerCore, idx: int) -> String:
	if idx < 0 or idx >= player.equips.size():
		return items_page(player, "equip")
	var inst := player.equips[idx]
	var id := String(inst.get("id", ""))
	var def := GameData.get_item(id)
	var atk: Array = def.get("atk", [0, 0])
	var max_dur := maxi(int(def.get("durability", 1)), 1)
	var lines: Array[String] = []
	lines.append(header("装备详情"))
	lines.append("名称：%s" % esc(player.item_name(id)))
	lines.append("说明：%s" % esc(String(def.get("desc", ""))))
	lines.append("使用等级：%d级" % int(def.get("req_level", 1)))
	lines.append("品质：%s  %s" % [esc(String(def.get("quality", "普通"))), "可交易" if bool(def.get("tradeable", false)) else "不可交易"])
	lines.append("负重：%d" % int(def.get("weight", 0)))
	lines.append("数量：1")
	lines.append("最小攻击：%d" % int(atk[0]))
	lines.append("最大攻击：%d" % int(atk[1]))
	lines.append("耐久：%d-%d" % [int(inst.get("dur", 0)), max_dur])
	lines.append("")
	if idx == player.hand:
		lines.append("[center]%s[/center]" % link("equip_off:%d" % idx, "卸下手持"))
	else:
		lines.append("[center]%s   %s[/center]" % [link("equip_use:%d" % idx, "使用手持"), link("back_game", "返回")])
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


# ---------- 城内地图 ----------

static func city_map() -> String:
	var lines: Array[String] = []
	lines.append(header(GameData.city_map_name))
	var row: Array[String] = []
	for scene: Dictionary in GameData.map_scenes():
		row.append(link("goto:%s" % String(scene.get("id", "")), String(scene.get("short", scene.get("name", "")))))
		if row.size() >= 4:
			lines.append(SEP.join(PackedStringArray(row)))
			row = []
	if not row.is_empty():
		lines.append(SEP.join(PackedStringArray(row)))
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


# ---------- 战斗 ----------

static func combat_page(engine: CombatEngine, player: PlayerCore, show_self: bool, notice: String) -> String:
	var lines: Array[String] = []
	if notice != "":
		lines.append("[color=red]%s[/color]" % esc(notice))
	lines.append(header("敌方属性"))
	lines.append("名称：%s" % esc(engine.monster_name))
	lines.append("等级：%d" % engine.monster_level)
	lines.append("攻击：%d-%d" % [engine.monster_atk_min, engine.monster_atk_max])
	lines.append("防御：%d" % engine.monster_def)
	lines.append("体力：%d/%d" % [engine.monster_hp, engine.monster_hp_max])
	lines.append("")
	lines.append("[center]%s   %s   %s   %s[/center]" % [
		link("attack", "攻击"),
		link("view", "查看"),
		link("combat_drug", "药品"),
		link("retreat", "撤退(%d铜贝)" % engine.retreat_cost()),
	])
	lines.append("你体力：%d/%d  攻击：%d-%d  防御：%d" % [
		player.hp_cur, player.max_hp(),
		player.atk_range().x, player.atk_range().y, player.defense(),
	])
	if show_self:
		var hand := player.hand_item()
		var hand_name := "空手" if hand.is_empty() else player.item_name(String(hand.get("id", "")))
		lines.append(dim("手持：%s  负重：%d/%d  铜贝：%d" % [esc(hand_name), player.weight(), player.weight_cap(), player.copper]))
	if not engine.log_lines.is_empty():
		lines.append("")
		for line in engine.log_lines:
			lines.append(dim(line))
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


static func win_page(engine: CombatEngine, player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("战斗胜利"))
	lines.append("战胜了%s！" % esc(engine.monster_name))
	if engine.monster_id == Rules.dungeon_monster() and player.location == Rules.dungeon_scene():
		lines.append("地宫击杀进度：%d/%d" % [player.dungeon_kills, Rules.dungeon_kill_goal()])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("back_game", "返回游戏"), link("combat_reward", "继续")])
	return join_lines(lines)


static func reward_page(engine: CombatEngine, player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("战利品"))
	lines.append("你体力：%d/%d" % [player.hp_cur, player.max_hp()])
	lines.append("经验：+%d" % engine.reward_exp)
	lines.append("贝钱：+%d" % engine.reward_copper)
	if engine.level_gained > 0:
		lines.append("[color=#ffd700]连升 %d 级！当前 %d 级。[/color]" % [engine.level_gained, player.level])
	if engine.reward_item != "":
		lines.append("获得装备：%s" % esc(player.item_name(engine.reward_item)))
	if engine.reward_equip != "":
		lines.append("获得装备：%s" % esc(player.item_name(engine.reward_equip)))
	if engine.weapon_broke_name != "":
		lines.append("[color=red]%s 已损坏！[/color]" % esc(engine.weapon_broke_name))
	lines.append("")
	lines.append("[center]%s[/center]" % link("combat_leave", "返回游戏"))
	return join_lines(lines)


static func combat_drug_page(engine: CombatEngine, player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("战斗 · 药品"))
	lines.append("你体力：%d/%d  %s体力：%d/%d" % [
		player.hp_cur, player.max_hp(), esc(engine.monster_name), engine.monster_hp, engine.monster_hp_max,
	])
	lines.append(dim("吃掉一瓶要花去一个回合，%s会趁机还手，看准了再用。" % engine.monster_name))
	var any := false
	for id: String in player.bag:
		var def := GameData.get_item(id)
		if String(def.get("type", "")) != "drug":
			continue
		any = true
		lines.append("%s ×%d 疗效+%d  %s" % [
			esc(String(def.get("name", id))), int(player.bag[id]), int(def.get("heal", 0)),
			link("combat_use:%s" % id, "[服用]"),
		])
	if not any:
		lines.append(dim("背包里已经没有药品了。"))
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("combat_back", "返回战斗"), link("retreat", "撤退(%d铜贝)" % engine.retreat_cost())])
	return join_lines(lines)


static func drug_result(player: PlayerCore, msg: String) -> String:
	var lines: Array[String] = []
	lines.append(header("药品"))
	lines.append(esc(msg))
	lines.append("体力：%d/%d" % [player.hp_cur, player.max_hp()])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("items:drug", "返回"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func lose_page(engine: CombatEngine, lost_copper: int, revive_scene_name: String) -> String:
	var lines: Array[String] = []
	lines.append(header("战斗失败"))
	lines.append("你被%s狠狠教训了一顿!" % esc(engine.monster_name))
	lines.append("丢失铜贝:%d" % lost_copper)
	lines.append("被好心人救回了城里。")
	lines.append(dim("（现在位置：%s）" % esc(revive_scene_name)))
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("combat_leave", "撤退"), link("combat_leave", "继续")])
	return join_lines(lines)


static func retreat_page(cost: int) -> String:
	var lines: Array[String] = []
	lines.append(header("撤退"))
	lines.append("你丢下 %d 铜贝，捂着伤口逃了回来。" % cost)
	lines.append("")
	lines.append("[center]%s[/center]" % link("combat_leave", "返回游戏"))
	return join_lines(lines)


# ---------- NPC / 子系统 ----------

static func npc_flavor_page(npc: Dictionary, player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header(String(npc.get("name", ""))))
	for line: String in npc.get("lines", []):
		lines.append(esc(line.replace("{昵称}", player.nickname)))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func notice_page(text: String, back_event: String, back_label: String) -> String:
	var lines: Array[String] = []
	lines.append(esc(text))
	lines.append("")
	lines.append("[center]%s[/center]" % link(back_event, back_label))
	return join_lines(lines)


static func welfare_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("福利官"))
	if player.welfare_claimable():
		lines.append("福利官：本周开始发放福利了！")
		lines.append("")
		lines.append("[center]%s[/center]" % link("welfare_claim", "领福利"))
	else:
		lines.append("福利官：本周的福利你已经领过了，下周再来吧。")
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func welfare_result(amount: int) -> String:
	var lines: Array[String] = []
	lines.append(header("福利官"))
	lines.append("福利官：省着花吧！")
	lines.append("铜贝：+%d" % amount)
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func church_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("神父(免费治疗)"))
	lines.append("神父(免费治疗)：我可怜的孩子，我有什么可以帮助你？我可以免费为你提供治疗的服务。不过你最好在战斗的时候能够学会吃药品，或者去商城买自动补血的药剂，很多地方也很危险，最好不要乱闯。")
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("heal", "治疗"), link("confess", "忏悔")])
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func heal_result(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("神父(免费治疗)"))
	lines.append("神父(免费治疗)：你的伤情有所好转，下次打怪记得多带点补充体力的药剂，在打怪的时候可以点击就可以补充体力了，体力药剂一般商店就有卖的,本次治疗体力+%d，当前体力%d" % [Rules.heal_amount(), player.hp_cur])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("heal", "继续治疗"), link("back_game", "返回")])
	return join_lines(lines)


static func confess_result(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("神父(免费治疗)"))
	if player.sin > 0:
		lines.append("神父(免费治疗)：你当前罪恶值为%d。当你感觉罪恶深重时，可以找我忏悔，减轻你的罪恶" % player.sin)
	else:
		lines.append("神父(免费治疗)：你当前罪恶值为%d，四大皆空，自信满满。当你感觉罪恶深重时，可以找我忏悔，减轻你的罪恶。" % player.sin)
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("confess", "忏悔"), link("back_game", "返回")])
	return join_lines(lines)


static func bank_main(player: PlayerCore) -> String:
	var can_deposit := player.copper / Rules.copper_per_silver()
	var lines: Array[String] = []
	lines.append(header("威尼斯银行"))
	lines.append("银行职员：现金带在身上可能会被抢走，这里提供最安全的现金保管，当你在游戏内消费时会自动从您的银行帐户支取，请不用担心。目前威尼斯银行单次存款最低额为 1银贝。您可以存入%d银贝！" % can_deposit)
	lines.append("银行职员：你现在存款%d银贝！" % player.bank_silver)
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("bank_deposit", "存款"), link("bank_withdraw", "取款")])
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func bank_deposit_page(player: PlayerCore) -> String:
	var per := Rules.copper_per_silver()
	var max_silver := player.copper / per
	var lines: Array[String] = []
	lines.append(header("银行 · 存款"))
	if max_silver <= 0:
		lines.append("银行职员：你现在不需要存款。")
	else:
		lines.append("银行职员：你可以存入%d银贝（1银贝=%d铜贝）。" % [max_silver, per])
		var parts: Array[String] = []
		for amount: int in [1, 10, 100]:
			if amount <= max_silver:
				parts.append(link("deposit:%d" % amount, "存%d银" % amount))
		parts.append(link("deposit:all", "全部存入(%d银)" % max_silver))
		lines.append(SEP.join(PackedStringArray(parts)))
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("bank", "返回银行"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func bank_withdraw_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("银行 · 取款"))
	if player.bank_silver <= 0:
		lines.append("银行职员：你的账户空空如也。")
	else:
		lines.append("银行职员：你当前存款%d银贝。" % player.bank_silver)
		var parts: Array[String] = []
		for amount: int in [1, 10, 100]:
			if amount <= player.bank_silver:
				parts.append(link("withdraw:%d" % amount, "取%d银" % amount))
		parts.append(link("withdraw:all", "全部取出(%d银)" % player.bank_silver))
		lines.append(SEP.join(PackedStringArray(parts)))
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("bank", "返回银行"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func bank_result(deposit: bool, silver: int) -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯银行"))
	if deposit:
		lines.append("银行职员：您的资金%d银贝已经成功存入帐户，感谢您的光临，每过一段时间本城银行有最佳客户评选活动，请您记得常来哦。" % silver)
	else:
		lines.append("银行职员：您的资金%d银贝已经成功取出，感谢您的光临，每过一段时间本城银行有最佳客户评选活动，请您记得常来哦。" % silver)
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("bank", "返回银行"), link("back_game", "返回游戏")])
	return join_lines(lines)


# ---------- 赌场 ----------

static func casino_main() -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯赌场"))
	lines.append("博彩MM：欢迎光临，您要选什么方式试试运气呢？本赌场服务费10%")
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("rps_page", "猜拳"), link("dice_page", "赌大小")])
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func dice_page() -> String:
	var lines: Array[String] = []
	lines.append(header("赌场 · 赌大小"))
	lines.append("博彩MM：赔率1赔5，下注即出结果，请下注。")
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [
		link("dice:big", "买大(%d铜 )" % Rules.casino_bet()),
		link("dice:small", "买小(%d铜 )" % Rules.casino_bet()),
	])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("again", "返回"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func dice_result(player: PlayerCore, dice: Array, won: bool, summary: String) -> String:
	var lines: Array[String] = []
	lines.append(header("赌场 · 赌大小"))
	lines.append("骰子：%d + %d + %d = %s" % [int(dice[0]), int(dice[1]), int(dice[2]), summary])
	if won:
		lines.append("博彩MM： %s，继续加油哦." % esc(player.nickname))
		lines.append("铜贝：+%d" % Rules.casino_win())
	else:
		lines.append("博彩MM： %s，继续加油吧." % esc(player.nickname))
		lines.append("铜贝：-%d" % Rules.casino_bet())
	lines.append("")
	lines.append("[center]%s   %s   %s[/center]" % [link("again", "再来一次"), link("back_game", "返回游戏"), link("dice_page", "返回")])
	return join_lines(lines)


static func casino_insufficient_line(gender: String) -> String:
	return "博彩MM：壮士，有钱老娘再来陪你玩...." if gender != "♀" else "博彩MM：靓女，有钱本少爷再来陪你玩...."


static func rps_page() -> String:
	var lines: Array[String] = []
	lines.append(header("赌场 · 猜拳"))
	lines.append("博彩MM：石头，剪刀，布，请出拳。")
	lines.append("")
	var bet := Rules.casino_bet()
	lines.append("[center]%s   %s   %s[/center]" % [
		link("rps:rock", "石头(%d铜 )" % bet),
		link("rps:scissors", "剪刀(%d铜 )" % bet),
		link("rps:paper", "布(%d铜 )" % bet),
	])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("again", "返回"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func rps_result(player: PlayerCore, my_move: String, mm_move: String, outcome: String) -> String:
	var lines: Array[String] = []
	lines.append(header("赌场 · 猜拳"))
	lines.append("你出了%s，博彩MM出了%s。" % [esc(my_move), esc(mm_move)])
	match outcome:
		"draw":
			lines.append("博彩MM：我出的也是%s，哈哈，再来！" % esc(mm_move))
		"win":
			lines.append("博彩MM： 123，我出%s，不行，再来！" % esc(mm_move))
			lines.append("铜贝：+%d" % Rules.casino_win())
		"lose":
			var variants := [
				"博彩MM：哈哈%s，败在老娘的石榴裙下，再来，再来！" % mm_move,
				"博彩MM：哈哈%s，还是老娘厉害，再来，再来！" % mm_move,
			]
			lines.append(esc(variants[randi() % variants.size()]))
			lines.append("铜贝：-%d" % Rules.casino_bet())
	lines.append("")
	lines.append("[center]%s   %s   %s[/center]" % [link("again", "再来一次"), link("back_game", "返回游戏"), link("rps_page", "返回")])
	return join_lines(lines)


# ---------- 市场 ----------

static func market_main(player: PlayerCore) -> String:
	var day := player.current_day()
	var lines: Array[String] = []
	lines.append(header("威尼斯市场"))
	lines.append("供应商：我这卖的都是本地特产，实在便宜。")
	for id: String in GameData.items:
		var def := GameData.get_item(id)
		if String(def.get("type", "")) != "goods":
			continue
		# 契约 trade-spec §4：威尼斯市场价切换为 Trade 引擎（产地 0.85 折，卖价=买价）
		var unit := Trade.price(id, Trade.VENICE, day)
		lines.append("▉%s %d铜贝/箱" % [esc(String(def.get("name", id))), unit])
		var parts: Array[String] = []
		for tier: int in def.get("tiers", []):
			parts.append(link("buy:%s:%d" % [id, tier], "%d箱" % tier))
		lines.append("　买：%s" % SEP.join(PackedStringArray(parts)))
	lines.append("我现有：金贝:%d 铜贝:%d" % [player.gold, player.copper])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("sell_page", "卖货"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func market_result(player: PlayerCore, msg: String) -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯市场"))
	lines.append(esc(msg))
	lines.append("我现有：金贝:%d 铜贝:%d" % [player.gold, player.copper])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("market", "返回市场"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func sell_page(player: PlayerCore) -> String:
	var day := player.current_day()
	var lines: Array[String] = []
	lines.append(header("威尼斯市场 · 卖货"))
	var any := false
	for id: String in player.bag:
		var def := GameData.get_item(id)
		if String(def.get("type", "")) != "goods":
			continue
		any = true
		var count := int(player.bag[id])
		# 与 _sell 同源：Trade 引擎价（同港零差价）
		var unit := Trade.price(id, Trade.VENICE, day)
		lines.append("▉%s ×%d（%d铜贝/箱）" % [esc(String(def.get("name", id))), count, unit])
		var parts: Array[String] = []
		for tier: int in def.get("tiers", []):
			if tier <= count:
				parts.append(link("sell:%s:%d" % [id, tier], "卖%d箱" % tier))
		parts.append(link("sell:%s:all" % id, "全部卖出"))
		lines.append("　%s" % SEP.join(PackedStringArray(parts)))
	if not any:
		lines.append("供应商：你两手空空，卖什么货？先去买点特产吧。")
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("market", "返回市场"), link("back_game", "返回游戏")])
	return join_lines(lines)


# ---------- 商店 / 铁匠（扩展契约 §4.3-§4.4） ----------

static func shop_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯商店"))
	lines.append("商人：远洋商队刚靠岸，这几样药剂最能救命。出门打怪，包里可不能缺了它们。")
	for id: String in GameData.items:
		var def := GameData.get_item(id)
		if String(def.get("type", "")) != "drug":
			continue
		var unit := int(def.get("price", int(def.get("buy_price", 0))))
		lines.append("▉%s 疗效+%d %d铜贝/瓶" % [esc(String(def.get("name", id))), int(def.get("heal", 0)), unit])
		var parts: Array[String] = []
		for tier: int in def.get("tiers", []):
			parts.append(link("buy_drug:%s:%d" % [id, tier], "买%d瓶" % tier))
		lines.append("　买：%s" % SEP.join(PackedStringArray(parts)))
	lines.append("我现有：金贝:%d 铜贝:%d" % [player.gold, player.copper])
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回游戏"))
	return join_lines(lines)


static func shop_result(player: PlayerCore, msg: String) -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯商店"))
	lines.append(esc(msg))
	lines.append("我现有：金贝:%d 铜贝:%d" % [player.gold, player.copper])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("shop", "返回商店"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func smith_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯铁匠铺"))
	lines.append("铁匠：炉火正旺，修修补补、打刀造剑，都是我的拿手活。")
	var hand := player.hand_item()
	if hand.is_empty():
		lines.append(dim("手持：空手（去打造一把趁手的兵器吧）"))
	else:
		var hid := String(hand.get("id", ""))
		var max_dur := maxi(int(GameData.get_item(hid).get("durability", 1)), 1)
		lines.append("手持：%s 耐久 %d/%d" % [esc(player.item_name(hid)), int(hand.get("dur", 0)), max_dur])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("repair_hand", "修理手持"), link("forge_page", "打造装备")])
	# 契约 trade-spec §7：多余装备回炉回收入口
	lines.append("[center]%s[/center]" % link("sell_equip_page", "出售装备"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func smith_result(player: PlayerCore, msg: String) -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯铁匠铺"))
	lines.append(esc(msg))
	lines.append("铜贝：%d" % player.copper)
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("smith", "返回铁匠铺"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func forge_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("铁匠铺 · 打造"))
	lines.append("铁匠：好铁配好手。材料给我备齐，工钱别短，装备马上出炉。")
	var any := false
	for id: String in GameData.items:
		var def := GameData.get_item(id)
		var forge: Dictionary = def.get("forge", {})
		if String(def.get("type", "")) != "equip" or forge.is_empty():
			continue
		any = true
		var atk: Array = def.get("atk", [0, 0])
		lines.append("▉%s（%d级 攻击%d-%d 耐久%d）" % [
			esc(String(def.get("name", id))), int(def.get("req_level", 1)),
			int(atk[0]), int(atk[1]), int(def.get("durability", 0)),
		])
		var mats: Dictionary = forge.get("materials", {})
		var mat_parts: Array[String] = []
		for mid: String in mats:
			mat_parts.append("%s×%d（有%d）" % [esc(player.item_name(mid)), int(mats[mid]), player.count_stack(mid)])
		lines.append("　材料：%s  工钱：%d铜贝" % [SEP.join(PackedStringArray(mat_parts)), int(forge.get("copper", 0))])
		if _forge_ready(player, id):
			lines.append("　%s" % link("forge:%s" % id, "[打造]"))
		else:
			lines.append("　%s" % dim("（材料或工钱不足，暂不能打造）"))
	if not any:
		lines.append(dim("暂无可打造的装备。图纸上还缺好铁。"))
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("smith", "返回铁匠铺"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func _forge_ready(player: PlayerCore, id: String) -> bool:
	var forge: Dictionary = GameData.get_item(id).get("forge", {})
	if forge.is_empty():
		return false
	var purse := player.copper + player.bank_silver * Rules.copper_per_silver()
	if purse < int(forge.get("copper", 0)):
		return false
	var mats: Dictionary = forge.get("materials", {})
	for mid: String in mats:
		if player.count_stack(mid) < int(mats[mid]):
			return false
	return true


# ---------- 码头 / 传送 ----------

static func teleport_page(player: PlayerCore) -> String:
	# 契约 trade-spec §6：world.json 就位后按大世界实况呈现（区域/10 港/当前所在）
	if not GameData.world_ports.is_empty():
		return _teleport_page_world(player)
	var lines: Array[String] = []
	lines.append(header("地中海传送"))
	lines.append("[b]航线区域：[/b]%s" % SEP.join(PackedStringArray(GameData.regions)))
	for i in GameData.ports.size():
		var port := GameData.ports[i]
		if _is_current_port(player, port):
			lines.append("▉%s（当前所在）" % esc(port))
		else:
			lines.append("▉%s" % link("tp:%d" % i, "%s(%d银)" % [port, Rules.teleport_cost_silver()]))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回码头"))
	return join_lines(lines)


## 大世界传送页：区域行按 world 实际区域呈现；全部港口列表，当前港不可选
static func _teleport_page_world(player: PlayerCore) -> String:
	var current := Trade.port_at(player.location)
	var region_seen: Array[String] = []
	for p: Dictionary in GameData.world_ports:
		var region := String(p.get("region", ""))
		if region != "" and not region_seen.has(region):
			region_seen.append(region)
	var lines: Array[String] = []
	lines.append(header("航海传送"))
	lines.append("[b]航线区域：[/b]%s" % SEP.join(PackedStringArray(region_seen)))
	for i in GameData.world_ports.size():
		var p: Dictionary = GameData.world_ports[i]
		var port_name := String(p.get("name", p.get("id", "")))
		if String(p.get("id", "")) == current:
			lines.append("▉%s（当前所在）" % esc(port_name))
		else:
			lines.append("▉%s" % link("tp:%d" % i, "%s(%d银)" % [port_name, Rules.teleport_cost_silver()]))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回码头"))
	return join_lines(lines)


## 传送到达提示页（契约 §6：成功 → goto 该港场景 + 船票提示）
static func tp_arrival_page(port_name: String, cost_copper: int) -> String:
	var lines: Array[String] = []
	lines.append(header("%s · 码头" % port_name))
	lines.append("船票花去 %d 铜贝。" % cost_copper)
	lines.append("船老板：到了，%s到了！下船当心脚滑，码头上小心扒手。" % port_name)
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "上岸"))
	return join_lines(lines)


# ---------- 航海贸易（契约 trade-spec §4-§5） ----------

## 港口行会市场：全部 12 贸易品本地价 + 🔥抢手标记 + 买卖档位
static func trade_market_page(player: PlayerCore, port_id: String, notice: String = "") -> String:
	var port_display := Trade.port_name(port_id)
	if port_display == port_id:
		port_display = String(GameData.get_scene(player.location).get("name", port_id))
	var region := String(Trade.port_def(port_id).get("region", "外海"))
	var day := player.current_day()
	var lines: Array[String] = []
	lines.append(header("%s · 商行" % port_display))
	lines.append("地区：%s　随身铜贝：%d" % [esc(region), player.copper])
	if notice != "":
		lines.append(esc(notice))
	lines.append("商人：产地便宜、抢手地价高，看什么看，看货！")
	for gid: String in Trade.trade_goods():
		var def := GameData.get_item(gid)
		var hot_mark := " [color=#ff5030]🔥抢手[/color]" if Trade.is_hot(gid, port_id, day) else ""
		lines.append("▉%s %d铜贝/箱%s" % [esc(String(def.get("name", gid))), Trade.price(gid, port_id, day), hot_mark])
		var buys: Array[String] = []
		var sells: Array[String] = []
		for tier in Trade.tiers_for(gid):
			buys.append(link("trade_buy:%s:%d" % [gid, int(tier)], "买%d箱" % int(tier)))
			sells.append(link("trade_sell:%s:%d" % [gid, int(tier)], "卖%d箱" % int(tier)))
		sells.append(link("trade_sell:%s:all" % gid, "全部卖出"))
		lines.append("　买：%s" % SEP.join(PackedStringArray(buys)))
		lines.append("　卖：%s" % SEP.join(PackedStringArray(sells)))
	lines.append("")
	lines.append("[center]%s[/center]" % link("goto:%s" % player.location, "返回港口"))
	return join_lines(lines)


## 酒保情报页：花铜板打听当日行情（rumor 链接；不买也有返回）
static func tavern_rumor_page(player: PlayerCore, port_id: String, notice: String = "") -> String:
	var port_display := Trade.port_name(port_id)
	if port_display == port_id:
		port_display = String(GameData.get_scene(player.location).get("name", port_id))
	var lines: Array[String] = []
	lines.append(header("%s · 酒保" % port_display))
	if notice != "":
		lines.append(esc(notice))
	lines.append("酒保：花 %d 铜，听我讲讲最近的行情。哪个港在抢什么货，我这儿门儿清。" % Rules.rumor_cost())
	lines.append("")
	lines.append("[center]%s[/center]" % link("rumor", "打听小道消息(%d铜)" % Rules.rumor_cost()))
	lines.append("")
	lines.append("[center]%s[/center]" % link("goto:%s" % player.location, "返回港口"))
	return join_lines(lines)


## 酒保情报结果页（情报必真：同 day 的 is_hot）
static func tavern_rumor_result(player: PlayerCore, rumor_lines: Array[String]) -> String:
	var lines: Array[String] = []
	lines.append(header("酒保 · 情报"))
	for line in rumor_lines:
		lines.append(esc(line))
	lines.append("铜贝：%d" % player.copper)
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("rumor", "再打听一条(%d铜)" % Rules.rumor_cost()), link("goto:%s" % player.location, "返回港口")])
	return join_lines(lines)


# ---------- 铁匠装备回收（契约 trade-spec §7） ----------

## 出售装备页：全部装备实例（名称/耐久/回收价=round(price×40%)），sell_equip:<idx>
static func sell_equip_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("铁匠铺 · 出售装备"))
	lines.append("铁匠：压箱底的旧家伙也值几个钱，拿来我按成色回收。")
	if player.equips.is_empty():
		lines.append(dim("你身上一件装备都没有。"))
	for i in player.equips.size():
		var inst := player.equips[i]
		var id := String(inst.get("id", ""))
		var def := GameData.get_item(id)
		var max_dur := maxi(int(def.get("durability", 1)), 1)
		var sell := Rules.equip_sell_price(int(def.get("price", 0)))
		var marker := "（手持）" if i == player.hand else ""
		lines.append("▉%s%s 耐久%d/%d 回收%d铜贝  %s" % [
			esc(player.item_name(id)), marker, int(inst.get("dur", 0)), max_dur, sell,
			link("sell_equip:%d" % i, "[出售]"),
		])
	lines.append("铜贝：%d" % player.copper)
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("smith", "返回铁匠铺"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func _is_current_port(player: PlayerCore, port: String) -> bool:
	return port == "威尼斯" and GameData.has_scene(player.location)


static func sail_page() -> String:
	return notice_page("威尼斯码头：　　　　　　暂未开发区域，请耐心等待", "back_game", "返回码头")


static func explorer_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("探险官"))
	lines.append("探险官：只有 5级以上的人才能进入威尼斯地宫，必须有 6人同行。在50分钟内在威尼斯地宫当中击杀40个抢劫者，在地宫中找秘密看守领取奖励。（每天只能进入一次）。找地宫大门的秘密看守交任务或离开。")
	lines.append("级别要求：5-15")
	lines.append("")
	var range_lv := Rules.dungeon_level_range()
	if player.level >= range_lv.x and player.level <= range_lv.y:
		lines.append("[center]%s[/center]" % link("dungeon_try", "进入威尼斯地宫"))
	else:
		lines.append(dim("（你的级别不符合要求。）"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


static func dungeon_page(player: PlayerCore) -> String:
	var scene := GameData.get_scene(Rules.dungeon_scene())
	var lines: Array[String] = []
	lines.append(header(String(scene.get("name", "威尼斯地宫"))))
	lines.append(esc(String(scene.get("desc", ""))))
	lines.append("")
	lines.append("任务：限时内击杀 %d 个抢劫者，找秘密看守领取奖励。" % Rules.dungeon_kill_goal())
	lines.append("击杀进度：%d/%d" % [player.dungeon_kills, Rules.dungeon_kill_goal()])
	lines.append("剩余时间：%s" % _mmss(player.dungeon_remaining_sec()))
	lines.append("")
	lines.append("[center]%s   %s   %s[/center]" % [
		link("fight:%s" % Rules.dungeon_monster(), "挑战抢劫者"),
		link("npc:%s:keeper" % Rules.dungeon_scene(), "秘密看守"),
		link("goto:%s" % Rules.dungeon_exit_scene(), "离开地宫"),
	])
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


static func dungeon_keeper_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("秘密看守"))
	lines.append("秘密看守：杀够 %d 个抢劫者再来找我领赏，你现在才 %d 个。" % [Rules.dungeon_kill_goal(), player.dungeon_kills])
	lines.append("剩余时间：%s" % _mmss(player.dungeon_remaining_sec()))
	lines.append("")
	lines.append("[center]%s[/center]" % link("goto:%s" % Rules.dungeon_scene(), "返回地宫"))
	return join_lines(lines)


static func dungeon_reward_page(copper_reward: int, gold_reward: int) -> String:
	var lines: Array[String] = []
	lines.append(header("秘密看守"))
	lines.append("秘密看守：干得漂亮！地宫的赏金如今是你的了，拿好，别在城门口露白。")
	lines.append("铜贝：+%d" % copper_reward)
	lines.append("[color=#ffd700]金贝：+%d[/color]" % gold_reward)
	lines.append("")
	lines.append("[center]%s[/center]" % link("goto:%s" % Rules.dungeon_exit_scene(), "离开地宫"))
	return join_lines(lines)


static func dungeon_timeout_page() -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯地宫"))
	lines.append("秘密看守：限时已到，地宫的规矩谁也不能破例。今天就到此为止，明天再来吧。")
	lines.append("")
	lines.append("[center]%s[/center]" % link("goto:%s" % Rules.dungeon_exit_scene(), "离开地宫"))
	return join_lines(lines)


# ---------- 工具 ----------

@warning_ignore("integer_division")
static func _mmss(total_sec: int) -> String:
	var s := maxi(total_sec, 0)
	return "%02d:%02d" % [s / 60, s % 60]


static func join_lines(lines: Array[String]) -> String:
	var out := ""
	for i in lines.size():
		out += lines[i]
		if i < lines.size() - 1:
			out += "\n"
	return out
