class_name Pages
## 页面构建器：把游戏状态渲染成 BBCode「页面」（对应原版的场景 HTML）。
## 页面内可点击元素一律 [url=事件]文案[/url]，事件由 EventRouter 分发。
## 橙色标题/蓝色链接致敬原版内嵌 CSS（h2 #ff9900、a blue）。

const HEADER_COLOR := "#ff9900"
const DIM_COLOR := "#9a9a9a"
const SEP := " . "
## ui-opt 契约 §3.1：加宽分隔（全角空格包间隔点）——城内地图/大世界等高密度入口防触屏误触
const WIDE_SEP := "　·　"
## 链接字号：触屏可交互文本的最小触控目标对齐顶部导航按钮（高 58px），
## 比正文（26）大一号并配合 PageView 行距，让可点击行高≈按钮高
const LINK_FONT_SIZE := 30

## 农场场景 id（契约 plan-v2 §5.3：nungcoeng 四块田）
const FARM_SCENE := "nungcoeng"
## 引路蜂物品 id（契约 §5.9：使用→野外传送列表）
const TP_BEE_ID := "yinlu_feng"
## 海皇碎片物品 id（契约 §5.4：集 3 交西利亚）
const SIREN_SHARD_ID := "haihuang_suipian"

## 品质颜色（契约 plan-v2 §5.12）：1-6=白/绿/蓝/紫/橙/红；
## 数据表 quality 兼容数字档位与中文档名（现有装备写「普通」等中文字符串）
const QUALITY_COLORS := {
	1: "#e8e8e8", 2: "#6fd66f", 3: "#4da6ff", 4: "#c07cff", 5: "#ff9900", 6: "#ff4040",
	"普通": "#e8e8e8", "精良": "#6fd66f", "稀有": "#4da6ff", "完美": "#c07cff", "史诗": "#ff9900", "传奇": "#ff4040",
}

const QUALITY_NAMES := {1: "普通", 2: "精良", 3: "稀有", 4: "完美", 5: "史诗", 6: "传奇"}

const GEM_BONUS_LABELS := {"atk": "攻击", "def": "防御", "agi": "敏捷", "hp": "体力"}


## 品质颜色值（数字档位与中文档名都认；无品质返回 ""=不着色）
static func quality_color(def: Dictionary) -> String:
	var q: Variant = def.get("quality", 0)
	if QUALITY_COLORS.has(q):
		return String(QUALITY_COLORS[q])
	return String(QUALITY_COLORS.get(int(q), ""))


## 品质档名（数字转中文；中文字符串原样）
static func quality_label(def: Dictionary) -> String:
	var q: Variant = def.get("quality", "")
	if q is String:
		return String(q)
	var n := int(q)
	return String(QUALITY_NAMES.get(n, ""))


## 品质着色的名称文本（装备/宝石名称着色用；无品质则原样转义）
static func quality_name(def: Dictionary, id: String) -> String:
	var label := String(def.get("name", id))
	var color := quality_color(def)
	if color == "":
		return esc(label)
	return "[color=%s]%s[/color]" % [color, esc(label)]


## 品质着色的链接（同 link()，但文字用品质色；无品质回退默认链接色）
static func quality_link(event: String, def: Dictionary, label: String = "") -> String:
	var text := label if label != "" else String(def.get("name", ""))
	var color := quality_color(def)
	if color == "":
		return link(event, text)
	return "[color=%s][url=%s][font_size=%d]%s[/font_size][/url][/color]" % [color, event, LINK_FONT_SIZE, esc(text)]


static func esc(s: String) -> String:
	# 先换占位符再还原：防止插入的 [lb]/[rb] 自身被二次替换（标签含 [] 时）
	return s.replace("[", "\u0001").replace("]", "\u0002").replace("\u0001", "[lb]").replace("\u0002", "[rb]")


static func link(event: String, label: String) -> String:
	return "[color=%s][url=%s][font_size=%d]%s[/font_size][/url][/color]" % [
		Rules.link_color(), event, LINK_FONT_SIZE, esc(label)]


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
	lines.append("")
	lines.append("[center]%s[/center]" % link("check_update", "检查更新"))
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


# ---------- 检查更新（标题页入口；请求经 UpdateChecker，结果由 EventRouter 回填） ----------

static func update_checking_page() -> String:
	var lines: Array[String] = []
	lines.append(header("检查更新"))
	lines.append("正在检查更新，请稍候……")
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_title", "返回标题"))
	return join_lines(lines)


## 更新检查结果页：失败可重试；新版展示更新日志并给下载入口（系统浏览器拉 APK）
static func update_result_page(result: Dictionary, local_version: String) -> String:
	var lines: Array[String] = []
	lines.append(header("检查更新"))
	var remote := String(result.get("version", "")).strip_edges().trim_prefix("v").trim_prefix("V")
	if not bool(result.get("ok", false)) or remote == "":
		lines.append("检查更新失败，可能是网络不太顺畅，稍后再试试。")
		lines.append("")
		lines.append("[center]%s[/center]" % link("check_update", "重试"))
	elif Rules.version_newer(remote, local_version):
		lines.append("发现新版本：[b]%s[/b]（当前 %s）" % [esc(remote), esc(local_version)])
		var notes := String(result.get("notes", "")).replace("\r\n", "\n").replace("\r", "\n").strip_edges()
		if notes != "":
			lines.append("")
			lines.append(dim(notes))
		lines.append("")
		if String(result.get("apk_url", "")) != "" or String(result.get("html_url", "")) != "":
			lines.append("[center]%s[/center]" % link("update_download", "前往下载"))
		else:
			lines.append(dim("（本次发布未附带安装包，请到发布页查看。）"))
	else:
		lines.append("当前已是最新版本：%s。" % esc(local_version))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_title", "返回标题"))
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
	var life_block := life_links(player, String(scene.get("id", "")))
	if not life_block.is_empty():
		lines.append("")
		lines.append(header("生活"))
		lines.append(SEP.join(PackedStringArray(life_block)))
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


## 场景页生活玩法条件入口（契约 plan-v2 §5.1-§5.4）：
## 无怪场景且满足打坐条件→打坐；fish/dive 场景→钓鱼(用活饵)/潜水；农场→种田
static func life_links(player: PlayerCore, scene_id: String) -> Array[String]:
	var links: Array[String] = []
	var monsters: Array = GameData.get_scene(scene_id).get("monsters", [])
	if monsters.is_empty() and meditate_ready(player):
		links.append(link("meditate", "打坐"))
	if Rules.life_fish_scenes().has(scene_id):
		links.append(link("fish", "钓鱼"))
		links.append(link("fish:bait", "用活饵钓鱼"))
	if Rules.life_dive_scenes().has(scene_id):
		links.append(link("dive", "潜水"))
	if scene_id == FARM_SCENE:
		links.append(link("farm", "农场"))
	return links


## 打坐条件（契约 §5.2）：持野球草人 + 等级达 req_level
static func meditate_ready(player: PlayerCore) -> bool:
	var def := GameData.get_item(Life.MEDITATE_TOOL_ID)
	if def.is_empty() or player.count_stack(Life.MEDITATE_TOOL_ID) <= 0:
		return false
	var eff: Dictionary = def.get("effect", {})
	return player.level >= maxi(int(eff.get("req_level", 10)), 1)


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
	if player.exp_buff_left > 0:
		lines.append("[color=#ffd700]经验加速：×%d（剩 %d 场）[/color]" % [player.exp_buff_mult, player.exp_buff_left])
	lines.append("体力：%d/%d" % [player.hp_cur, player.max_hp()])
	lines.append("攻击：%d-%d" % [atk.x, atk.y])
	lines.append("防御：%d" % player.defense())
	lines.append("装备：%s" % esc(hand_name))
	lines.append("负重：%d/%d" % [player.weight(), player.weight_cap()])
	lines.append("生活体力：%d/%d" % [player.stamina, player.max_stamina()])
	if player.streak > 0:
		lines.append("[color=#ffd700]连胜：%d  士气：攻击+%d%%[/color]" % [
			player.streak, player.momentum * Rules.combat_momentum_atk_pct_per()])
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
				var id := String(inst.get("id", ""))
				var def := GameData.get_item(id)
				var max_dur := maxi(int(def.get("durability", 1)), 1)
				var tag := _equip_tag(i, player)
				var label := "%s%s 耐久%d/%d" % [String(def.get("name", id)), tag, int(inst.get("dur", 0)), max_dur]
				lines.append(quality_link("equip_view:%d" % i, def, label))
		"other":
			var any := false
			for id: String in player.bag:
				var def := GameData.get_item(id)
				var t := String(def.get("type", ""))
				if t == "goods":
					any = true
					lines.append("%s ×%d" % [esc(String(def.get("name", id))), int(player.bag[id])])
				elif t == "item":
					any = true
					var action := ""
					var eff: Dictionary = def.get("effect", {})
					if String(eff.get("kind", "")) == "quest_item":
						action = dim("[任务物品]")
					elif not eff.is_empty():
						action = link("use_item:%s" % id, "[使用]")
					lines.append("%s ×%d %s  %s" % [
						quality_name(def, id), int(player.bag[id]), _shop_effect_text(def), action])
			if any:
				lines.append(dim("（长串货去市场卖，功能道具点「使用」。）"))
			else:
				lines.append(dim("暂无杂物。可以去市场买些本地特产。"))
		"gem":
			var any_gem := false
			for id: String in player.bag:
				var def := GameData.get_item(id)
				if String(def.get("type", "")) != "gem" or int(player.bag[id]) <= 0:
					continue
				any_gem = true
				var bonus: Dictionary = def.get("bonus", {})
				var bparts: Array[String] = []
				for k: String in bonus:
					bparts.append("%s+%d" % [String(GEM_BONUS_LABELS.get(k, k)), int(bonus[k])])
				lines.append("%s ×%d（%s）" % [quality_name(def, id), int(player.bag[id]), SEP.join(bparts)])
			if any_gem:
				lines.append(dim("（去铁匠铺把宝石嵌进带插槽的装备。）"))
				lines.append("[center]%s[/center]" % link("smith_gem", "前往镶嵌"))
			else:
				lines.append(dim("暂无宝石。矿洞的怪物身上偶尔能摸到，博士的助手也能炼出来。"))
		"drug":
			var any_drug := false
			for id: String in player.bag:
				var def := GameData.get_item(id)
				if String(def.get("type", "")) != "drug":
					continue
				any_drug = true
				lines.append("%s ×%d %s  %s" % [
					esc(String(def.get("name", id))), int(player.bag[id]), drug_effect_text(def),
					link("use_drug:%s" % id, "[使用]"),
				])
			if not any_drug:
				lines.append(dim("暂无药品。神父的免费治疗倒是一直都在。"))
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


## 装备实例标记（手持/护甲/强化/绑定），物品列表与铁匠页共用
static func _equip_tag(idx: int, player: PlayerCore) -> String:
	if idx < 0 or idx >= player.equips.size():
		return ""
	var inst: Dictionary = player.equips[idx]
	var tags: Array[String] = []
	if idx == player.hand:
		tags.append("手持")
	var slot := String(GameData.get_item(String(inst.get("id", ""))).get("slot", "weapon"))
	if idx == player.armor_idx:
		tags.append("已穿戴")
	elif slot == "armor":
		tags.append("护甲")
	if int(inst.get("enhance", 0)) > 0:
		tags.append("+%d" % int(inst.get("enhance", 0)))
	if bool(inst.get("bound", false)):
		tags.append("绑定")
	if tags.is_empty():
		return ""
	return "（%s）" % " ".join(PackedStringArray(tags))


static func equip_detail(player: PlayerCore, idx: int) -> String:
	if idx < 0 or idx >= player.equips.size():
		return items_page(player, "equip")
	var inst := player.equips[idx]
	var id := String(inst.get("id", ""))
	var def := GameData.get_item(id)
	var is_armor := String(def.get("slot", "weapon")) == "armor"
	var max_dur := maxi(int(def.get("durability", 1)), 1)
	var lines: Array[String] = []
	lines.append(header("装备详情"))
	lines.append("名称：%s" % quality_name(def, id))
	lines.append("说明：%s" % esc(String(def.get("desc", ""))))
	lines.append("类型：%s  使用等级：%d级" % ["护甲" if is_armor else "武器", int(def.get("req_level", 1))])
	var trade_text := "可交易" if bool(def.get("tradeable", false)) else "不可交易"
	if bool(inst.get("bound", false)):
		trade_text += "（已绑定）"
	lines.append("品质：%s  %s" % [esc(quality_label(def)), trade_text])
	lines.append("负重：%d  强化：+%d" % [int(def.get("weight", 0)), maxi(int(inst.get("enhance", 0)), 0)])
	if is_armor:
		lines.append("防御：%d" % maxi(int(def.get("def", 0)), 0))
	else:
		var atk: Array = def.get("atk", [0, 0])
		lines.append("攻击：%d-%d" % [int(atk[0]), int(atk[1])])
	var affix: Array[String] = []
	if int(def.get("agility", 0)) > 0:
		affix.append("敏捷+%d" % int(def.get("agility", 0)))
	if int(def.get("lucky", 0)) > 0:
		affix.append("幸运+%d" % int(def.get("lucky", 0)))
	if int(def.get("poison_res", 0)) > 0:
		affix.append("毒抗+%d" % int(def.get("poison_res", 0)))
	if not affix.is_empty():
		lines.append("词条：%s" % SEP.join(affix))
	var slots := maxi(int(def.get("slots", 0)), 0)
	if slots > 0:
		var gems: Array = inst.get("gems", [])
		var gem_parts: Array[String] = []
		for g in gems:
			var gid := String(g)
			gem_parts.append(quality_name(GameData.get_item(gid), gid))
		var gem_text := SEP.join(gem_parts) if not gem_parts.is_empty() else "空"
		lines.append("宝石：%s（插槽 %d/%d）" % [gem_text, gems.size(), slots])
	lines.append("耐久：%d-%d" % [int(inst.get("dur", 0)), max_dur])
	lines.append("")
	if is_armor:
		if idx == player.armor_idx:
			lines.append("[center]%s   %s[/center]" % [link("armor_off:%d" % idx, "脱下护甲"), link("back_game", "返回")])
		else:
			lines.append("[center]%s   %s[/center]" % [link("equip_armor:%d" % idx, "穿戴护甲"), link("back_game", "返回")])
	elif idx == player.hand:
		lines.append("[center]%s[/center]" % link("equip_off:%d" % idx, "卸下手持"))
	else:
		lines.append("[center]%s   %s[/center]" % [link("equip_use:%d" % idx, "使用手持"), link("back_game", "返回")])
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


# ---------- 城内地图 ----------

static func city_map() -> String:
	# ui-opt 契约 §3.1：每行 4→3 个入口 + 全角加宽分隔 + 行间空行，防相邻误触（事件词全部不变）
	var lines: Array[String] = []
	lines.append(header(GameData.city_map_name))
	var rows: Array[String] = []
	var row: Array[String] = []
	for scene: Dictionary in GameData.map_scenes():
		row.append(link("goto:%s" % String(scene.get("id", "")), String(scene.get("short", scene.get("name", "")))))
		if row.size() >= 3:
			rows.append(WIDE_SEP.join(PackedStringArray(row)))
			row = []
	if not row.is_empty():
		rows.append(WIDE_SEP.join(PackedStringArray(row)))
	for i in rows.size():
		if i > 0:
			lines.append("")
		lines.append(rows[i])
	lines.append("")
	lines.append("[center]%s[/center]" % link("worldmap", "大世界"))
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
	var actions: Array[String] = [
		link("attack", "攻击"),
		link("view", "查看"),
		link("combat_drug", "药品"),
		link("retreat", "撤退(%d铜贝)" % engine.retreat_cost()),
	]
	# 攻击术（契约 plan-v2 §5：已学 attack 且本场未用时显示）
	if player.has_skill("attack") and not engine.skill_used_this_fight:
		actions.append(link("skill_cast", "攻击术(%d体力)" % Rules.combat_skill_stamina()))
	lines.append("[center]%s[/center]" % SEP.join(actions))
	var momentum_text := ""
	if player.momentum > 0:
		momentum_text = "  士气：攻击+%d%%" % (player.momentum * Rules.combat_momentum_atk_pct_per())
	lines.append("你体力：%d/%d  攻击：%d-%d  防御：%d%s" % [
		player.hp_cur, player.max_hp(),
		player.atk_range().x, player.atk_range().y, player.defense(), momentum_text,
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
	var qa: Dictionary = player.quest_andrew
	if String(qa.get("state", "")) == "active" and int(qa.get("day", -1)) == player.current_day() \
			and player.location != Rules.dungeon_scene():
		lines.append("试炼进度：%d/%d" % [int(qa.get("kills", 0)), Rules.quest_andrew_kills()])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("back_game", "返回游戏"), link("combat_reward", "继续")])
	return join_lines(lines)


static func reward_page(engine: CombatEngine, player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("战利品"))
	lines.append("你体力：%d/%d" % [player.hp_cur, player.max_hp()])
	lines.append("经验：+%d" % engine.reward_exp)
	if engine.exp_mult > 1:
		lines.append("[color=#ffd700]经验加速丹生效：经验×%d（剩 %d 场）[/color]" % [engine.exp_mult, player.exp_buff_left])
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
		lines.append("%s ×%d %s  %s" % [
			esc(String(def.get("name", id))), int(player.bag[id]), drug_effect_text(def),
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


## 药品效果文案：体力药=疗效+X；加速丹=经验×N（M场）
static func drug_effect_text(def: Dictionary) -> String:
	if def.has("exp_buff"):
		var buff: Dictionary = def.get("exp_buff", {})
		return "经验×%d（%d场）" % [int(buff.get("multiplier", 10)), int(buff.get("battles", 10))]
	return "疗效+%d" % int(def.get("heal", 0))


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

## NPC 对白行渲染（flavor 与新 kind 页面共用，避免五处复制）：
## {昵称} 占位符替换；行首孤立逗号视为缺省的称呼位，自动补昵称
## （酒馆老板✅原文以「，欢迎来到这个世界！」起句，原版渲染时逗号前是玩家昵称）
static func npc_line(line: String, player: PlayerCore) -> String:
	var text := line.replace("{昵称}", player.nickname)
	if text.begins_with("，") or text.begins_with(","):
		text = player.nickname + text
	return text


static func npc_flavor_page(npc: Dictionary, player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header(String(npc.get("name", ""))))
	for line: String in npc.get("lines", []):
		lines.append(esc(npc_line(line, player)))
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
	if not player.gift_claimed:
		# 契约 plan-v2 §5.7：全服预约礼包一次性领取
		lines.append("")
		lines.append("福利官：对了，全服预约的礼包还没人来领，一人一份，先到先得。")
		lines.append("[center]%s[/center]" % link("gift_claim", "领取预约礼包"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("gm_password", "纵横四海"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## GM 彩蛋密码盘：6 位密码框 + 9 个数字键（1-9）+ 清空/确认。
## 数字键加大（[font_size=40] + U+3000 填充、键间 ≥2 全角空格、行间空行，ui-opt 契约 §3.1）防误触。
## 密码错误的反馈由 EventRouter 处理（无任何提示），本页只管呈现。
static func gm_password_page(entered: String) -> String:
	var lines: Array[String] = []
	lines.append(header("福利官"))
	lines.append("福利官：（四下张望，压低声音）自己人才知道规矩——报上暗号，好东西自然有你的份。")
	lines.append("")
	var slots: Array[String] = []
	for i in 6:
		slots.append("●" if i < entered.length() else "＿")
	lines.append("[center][b][font_size=40]%s[/font_size][/b][/center]" % " ".join(PackedStringArray(slots)))
	lines.append(dim("（请输入 6 位数字密码）"))
	lines.append("")
	# ui-opt 契约 §3.1：数字键 [font_size=40] + U+3000 填充，键间 ≥2 全角空格、行间空行
	for row_i in 3:
		if row_i > 0:
			lines.append("")
		var cells: Array[String] = []
		for col in 3:
			var d := row_i * 3 + col + 1
			cells.append("[color=%s][url=gm_pwd:%d][font_size=40]　%d　[/font_size][/url][/color]" % [
				Rules.link_color(), d, d])
		lines.append("[center]%s[/center]" % "　　".join(PackedStringArray(cells)))
	lines.append("")
	# ui-opt 契约 §3.1：清空/确认行同样加宽分隔
	lines.append("[center]%s[/center]" % WIDE_SEP.join(PackedStringArray([
		link("gm_pwd:clear", "清空"), link("gm_pwd_ok", "确认")])))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## GM 彩蛋领奖页：只展示实际到手的奖励（可重复触发）
static func gm_reward_page(player: PlayerCore, pill_id: String, pill_count: int, knife_id: String) -> String:
	var lines: Array[String] = []
	lines.append(header("福利官"))
	lines.append("福利官：暗号对上了！东西拿好，天知地知你知我知。")
	if pill_count > 0:
		lines.append("获得道具：%s ×%d" % [esc(player.item_name(pill_id)), pill_count])
		# ui-opt 契约 §3.2：叠加口径说明（场次随服用累加）
		lines.append(dim("加速效果可叠加：每颗×10，持续 10 场。"))
	if knife_id != "":
		lines.append("获得装备：%s" % esc(player.item_name(knife_id)))
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

## 商店在售过滤（契约 plan-v2 §2.1）：price>0 的药品与功能道具；
## 任务物品/礼包/price=0 特殊道具（体力宝/技能书/龙泉水等）不进商店；宝石走炼金与掉落
static func _shop_entry_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in GameData.items:
		var def := GameData.get_item(id)
		var t := String(def.get("type", ""))
		if int(def.get("price", 0)) <= 0:
			continue
		if t == "drug":
			out.append(id)
		elif t == "item":
			var eff: Dictionary = def.get("effect", {})
			var kind := String(eff.get("kind", ""))
			if kind != "quest_item" and kind != "gift":
				out.append(id)
	return out


## 商店行效果文案（药品=疗效/经验场数；功能道具按 effect kind）
static func _shop_effect_text(def: Dictionary) -> String:
	if String(def.get("type", "")) == "drug":
		if def.has("exp_buff"):
			var buff: Dictionary = def.get("exp_buff", {})
			return "经验×%d（%d场）" % [int(buff.get("multiplier", 10)), int(buff.get("battles", 10))]
		return "疗效+%d" % int(def.get("heal", 0))
	var eff: Dictionary = def.get("effect", {})
	match String(eff.get("kind", "")):
		"stamina":
			return "生活体力+%d" % int(eff.get("value", 0))
		"exp_buff":
			return "经验+%d%%（%d小时）" % [
				int(round((float(eff.get("multiplier", 2.0)) - 1.0) * 100.0)), maxi(int(eff.get("hours", 1)), 1)]
		"clear_buff":
			return "清除卡片效果"
		"weight":
			return "负重上限+%d" % int(eff.get("value", 0))
		"rename":
			return "更改昵称"
		"teleport_wild":
			return "传送到野外"
		"skill":
			return "学习技能"
		"meditate_tool":
			return "打坐修行用具"
		"bait":
			return "稀有鱼饵"
		"seed":
			return "农场种子"
		_:
			return ""


static func shop_page(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("威尼斯商店"))
	lines.append("商人：远洋商队刚靠岸，药剂、干粮、杂货这几样最救命。出门在外，包里可不能缺了它们。")
	for id: String in _shop_entry_ids():
		var def := GameData.get_item(id)
		var unit := int(def.get("price", 0))
		lines.append("▉%s %s %d铜贝" % [esc(String(def.get("name", id))), _shop_effect_text(def), unit])
		var tiers: Array = def.get("tiers", [])
		if tiers.is_empty():
			tiers = [1, 10]
		var parts: Array[String] = []
		for tier in tiers:
			parts.append(link("buy_drug:%s:%d" % [id, int(tier)], "买%d" % int(tier)))
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
	lines.append("[center]%s   %s   %s[/center]" % [
		link("repair_hand", "修理手持"), link("forge_page", "打造装备"), link("smith_enhance", "强化装备")])
	lines.append("[center]%s   %s[/center]" % [link("smith_gem", "宝石镶嵌"), link("sell_equip_page", "出售装备")])
	# 契约 plan-v2 §2.1：price>0 的装备在铁匠处在售
	var on_sale := 0
	for id: String in GameData.items:
		var def := GameData.get_item(id)
		if String(def.get("type", "")) != "equip" or int(def.get("price", 0)) <= 0:
			continue
		on_sale += 1
		if on_sale == 1:
			lines.append("")
			lines.append(header("在售装备"))
		var stat_text := ""
		if String(def.get("slot", "weapon")) == "armor":
			stat_text = "防御%d" % maxi(int(def.get("def", 0)), 0)
		else:
			var atk: Array = def.get("atk", [0, 0])
			stat_text = "攻击%d-%d" % [int(atk[0]), int(atk[1])]
		lines.append("▉%s（%d级 %s）%d铜贝  %s" % [
			esc(String(def.get("name", id))), int(def.get("req_level", 1)), stat_text,
			int(def.get("price", 0)), link("buy_equip:%s" % id, "[购买]")])
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

## 出售装备页：全部装备实例（名称/耐久/回收价=round(price×40%)），sell_equip:<idx>。
## 同名多件给批量入口 sell_equip_all:<id>；notice 显示上一笔成交（卖出后留在本页继续出售）
static func sell_equip_page(player: PlayerCore, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header("铁匠铺 · 出售装备"))
	lines.append("铁匠：压箱底的旧家伙也值几个钱，拿来我按成色回收。")
	if notice != "":
		lines.append("[color=#6fd66f]%s[/color]" % esc(notice))
	if player.equips.is_empty():
		lines.append(dim("你身上一件装备都没有。"))
	for i in player.equips.size():
		var inst := player.equips[i]
		var id := String(inst.get("id", ""))
		var def := GameData.get_item(id)
		var max_dur := maxi(int(def.get("durability", 1)), 1)
		var sell := Rules.equip_sell_price(int(def.get("price", 0)))
		var bound := bool(inst.get("bound", false))
		var same := 0
		for other: Dictionary in player.equips:
			# 批量入口只数可卖件（绑定装备无法出售，主进程裁决）
			if String(other.get("id", "")) == id and not bool(other.get("bound", false)):
				same += 1
		var actions: Array[String] = []
		if bound:
			actions.append(dim("［绑定装备无法出售］"))
		else:
			actions.append(link("sell_equip:%d" % i, "[出售]"))
			if same >= 2:
				actions.append(link("sell_equip_all:%s" % id, "[全部出售%d件]" % same))
		lines.append("▉%s%s 耐久%d/%d 回收%d铜贝  %s" % [
			esc(player.item_name(id)), _equip_tag(i, player), int(inst.get("dur", 0)), max_dur, sell,
			SEP.join(PackedStringArray(actions)),
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


# ---------- 生活玩法（契约 plan-v2 §3/§5） ----------

## 通用道具使用结果页（use_item 各分支共用）
static func item_used_page(player: PlayerCore, msg: String) -> String:
	var lines: Array[String] = []
	lines.append(header("物品"))
	lines.append(esc(msg))
	lines.append("生活体力：%d/%d  负重：%d/%d" % [
		player.stamina, player.max_stamina(), player.weight(), player.weight_max()])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("items:other", "返回物品"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func meditate_result(player: PlayerCore, res: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(header("打坐"))
	lines.append(esc(String(res.get("msg", ""))))
	if bool(res.get("ok", false)):
		lines.append("修为精进：经验 +%d" % int(res.get("exp", 0)))
	lines.append("生活体力：%d/%d" % [player.stamina, player.max_stamina()])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("meditate", "再打坐"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func fish_result(player: PlayerCore, res: Dictionary, use_bait: bool) -> String:
	var lines: Array[String] = []
	lines.append(header("钓鱼"))
	lines.append(esc(String(res.get("msg", ""))))
	lines.append("生活体力：%d/%d  活饵：×%d" % [
		player.stamina, player.max_stamina(), player.count_stack(Life.BAIT_ID)])
	lines.append("")
	lines.append("[center]%s   %s   %s[/center]" % [
		link("fish", "再钓一次"), link("fish:bait", "用活饵再钓") if use_bait else link("fish:bait", "换活饵钓"),
		link("back_game", "返回游戏")])
	return join_lines(lines)


static func dive_result(player: PlayerCore, res: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(header("潜水"))
	lines.append(esc(String(res.get("msg", ""))))
	lines.append("生活体力：%d/%d  海皇碎片：×%d" % [
		player.stamina, player.max_stamina(), player.count_stack(SIREN_SHARD_ID)])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("dive", "再潜一次"), link("back_game", "返回游戏")])
	return join_lines(lines)


static func farm_page(player: PlayerCore, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header("农场"))
	lines.append("四块田翻得整整齐齐，播下种子就等着收获。")
	var seed_count := 0
	for id: String in player.bag:
		var eff: Dictionary = GameData.get_item(id).get("effect", {})
		if String(eff.get("kind", "")) == "seed":
			seed_count += int(player.bag[id])
	lines.append("种子：×%d  生活体力：%d/%d（播种一次耗 %d）" % [
		seed_count, player.stamina, player.max_stamina(), Rules.life_farm_stamina()])
	if notice != "":
		lines.append(esc(notice))
	var now := int(Time.get_unix_time_from_system())
	var mature := 0
	for i in player.farm_plots.size():
		var plot: Dictionary = player.farm_plots[i]
		var name_text := "空地"
		var status := ""
		if plot.is_empty():
			if seed_count > 0 and player.stamina >= Rules.life_farm_stamina():
				status = link("farm_plant:%d" % i, "[播种]")
			else:
				status = dim("（缺种子或体力不足）")
		else:
			name_text = player.item_name(String(plot.get("seed_id", "")))
			var left := maxi(Rules.life_farm_grow_sec() - (now - maxi(int(plot.get("planted_unix", 0)), 0)), 0)
			if left <= 0:
				mature += 1
				status = "[color=#6fd66f]已成熟[/color]"
			else:
				status = dim("生长中（剩 %s）" % _mmss(left))
		lines.append("▉第%d块田：%s %s" % [i + 1, esc(name_text), status])
	if mature > 0:
		lines.append("[center]%s[/center]" % link("farm_harvest", "收获成熟作物(%d块)" % mature))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回农场"))
	return join_lines(lines)


## 引路蜂可去的野外场景（契约 §5.9）：on_map=false 全部野外，不含地宫与港口
static func wild_scenes() -> Array[String]:
	var out: Array[String] = []
	var port_scenes := {}
	for p: Dictionary in GameData.world_ports:
		port_scenes[String(p.get("scene", p.get("id", "")))] = true
	for id: String in GameData.scene_order:
		var scene: Dictionary = GameData.scenes_by_id[id]
		if bool(scene.get("on_map", false)):
			continue
		if id == Rules.dungeon_scene() or port_scenes.has(id):
			continue
		if (scene.get("exits", []) as Array).is_empty():
			continue
		out.append(id)
	return out


static func wild_tp_page(player: PlayerCore, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header("引路蜂"))
	lines.append("引路蜂振翅引路——选一处野外，它便带你瞬移过去（消耗一只引路蜂）。")
	lines.append("持有引路蜂：×%d" % player.count_stack(TP_BEE_ID))
	if notice != "":
		lines.append(esc(notice))
	for sid: String in wild_scenes():
		var scene := GameData.get_scene(sid)
		var label := String(scene.get("name", sid))
		if sid == player.location:
			lines.append("▉%s（当前所在）" % esc(label))
		else:
			lines.append("▉%s" % link("wild_tp:%s" % sid, label))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## 大世界地图（契约 §5.11 最终裁决：纯展示只读，不放传送按钮，避免变相免费传送）
static func worldmap_page(player: PlayerCore) -> String:
	var groups: Array = [
		["矿山深处", ["kuaangsan", "kuongdung"]],
		["废墟与堡垒", ["hongjoe", "feizoi", "biltou"]],
		["荒野湿地", ["coujin", "moucoeng", "zamlam", "mezai", "zozik", "gucyunlei", "hauwaan"]],
		["农场海岸", ["nungcoeng", "nungcoeng1", "haitan", "tsienhoi", "ngoanzo"]],
		["学院重地", ["soenmon"]],
	]
	var lines: Array[String] = []
	lines.append(header("大世界"))
	lines.append(dim("威尼斯城外的广袤天地。此处仅作指路之用：步行沿出口前进，跨海请去码头乘船。"))
	for g: Array in groups:
		var row: Array[String] = []
		for sid: String in g[1]:
			if not GameData.has_scene(sid):
				continue
			var label := String(GameData.get_scene(sid).get("name", sid))
			if sid == player.location:
				label += "（当前所在）"
			row.append(esc(label))
		if row.is_empty():
			continue
		lines.append("")
		lines.append("[b]%s[/b]" % esc(String(g[0])))
		# ui-opt 契约 §3.1：组内场景名 3 个/行折行，分隔同样加宽
		var chunk: Array[String] = []
		for label_text: String in row:
			chunk.append(label_text)
			if chunk.size() >= 3:
				lines.append(WIDE_SEP.join(PackedStringArray(chunk)))
				chunk = []
		if not chunk.is_empty():
			lines.append(WIDE_SEP.join(PackedStringArray(chunk)))
		var first_scene := GameData.get_scene(String(g[1][0]))
		var flavor := String(first_scene.get("desc", "")).split("。")[0]
		if flavor != "":
			lines.append(dim(flavor + "。"))
	lines.append("")
	lines.append("地宫须由北城门的探险官带领进入；城区街坊见「城内地图」。")
	lines.append("[center]%s[/center]" % link("map", "城内地图"))
	lines.append("")
	lines.append(footer())
	return join_lines(lines)


# ---------- 新 NPC 页面（契约 plan-v2 §3 新 kind） ----------

## 酒馆主页（老板 kind=tavern）：新手指引对白 + 同场人物入口
static func tavern_page(scene: Dictionary, player: PlayerCore) -> String:
	var lines: Array[String] = []
	var boss := {}
	for npc: Dictionary in scene.get("npcs", []):
		if String(npc.get("kind", "")) == "tavern":
			boss = npc
			break
	lines.append(header(String(boss.get("name", "老板"))))
	for line: String in boss.get("lines", []):
		lines.append(esc(npc_line(line, player)))
	var others: Array[String] = []
	for npc: Dictionary in scene.get("npcs", []):
		if String(npc.get("kind", "")) == "tavern":
			continue
		others.append(link("npc:%s:%s" % [String(scene.get("id", "")), String(npc.get("id", ""))], String(npc.get("name", ""))))
	if not others.is_empty():
		lines.append("")
		lines.append(header("店里还有"))
		lines.append(SEP.join(others))
	lines.append(dim("朗姆酒气与烤鱼香里，各国水手把远方的传闻搅在一起。"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## 德罗西（kind=circus）：马戏团八卦 + 动物皮收购（鹅毛/狼皮=卖价120%，契约 §5.10）
const CIRCUS_SKINS := ["emao", "langpi"]
const CIRCUS_PRICE_PCT := 120


static func circus_unit_price(id: String) -> int:
	var sell := int(GameData.get_item(id).get("sell_price", 0))
	return maxi(int(round(float(sell) * float(CIRCUS_PRICE_PCT) / 100.0)), 1)


static func circus_page(player: PlayerCore, npc: Dictionary, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header(String(npc.get("name", "德罗西"))))
	for line: String in npc.get("lines", []):
		lines.append(esc(npc_line(line, player)))
	lines.append(dim("（马戏团的帐篷常驻酒馆后院，动物们的吃喝拉撒都归德罗西管。兽皮给动物们做垫子，他常年高价收。）"))
	if notice != "":
		lines.append("[color=#6fd66f]%s[/color]" % esc(notice))
	lines.append(header("动物皮收购"))
	for id: String in CIRCUS_SKINS:
		var def := GameData.get_item(id)
		if def.is_empty():
			continue
		var have := player.count_stack(id)
		var unit := circus_unit_price(id)
		lines.append("▉%s 收%d铜贝/张（持有×%d，市场卖价%d）" % [
			esc(String(def.get("name", id))), unit, have, int(def.get("sell_price", 0))])
		if have > 0:
			lines.append("　%s   %s" % [
				link("circus_sell:%s:1" % id, "卖1张"),
				link("circus_sell:%s:all" % id, "全部卖出(%d铜贝)" % (unit * have))])
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## 博士的助手（kind=alchemist）：炼金兑换（config.smith.alchemy）
static func alchemy_page(player: PlayerCore, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header("博士的助手"))
	lines.append("助手：老师的兑换生意由我照看——材料备齐、铜贝给够，东西马上炼给你。")
	if notice != "":
		lines.append(esc(notice))
	var recipes := Rules.smith_alchemy()
	for i in recipes.size():
		var recipe: Dictionary = recipes[i]
		var give: Dictionary = recipe.get("give", {})
		var get_d: Dictionary = recipe.get("get", {})
		var mat_parts: Array[String] = []
		var ready := true
		for mid: String in give:
			var need := int(give[mid])
			if mid == "copper":
				continue
			mat_parts.append("%s×%d（有%d）" % [esc(player.item_name(mid)), need, player.count_stack(mid)])
			if player.count_stack(mid) < need:
				ready = false
		var copper := int(give.get("copper", 0))
		if copper > 0:
			mat_parts.append("%d铜贝" % copper)
		var gid := String(get_d.get("id", ""))
		var gn := maxi(int(get_d.get("n", 1)), 1)
		lines.append("▉%s×%d ← %s" % [esc(player.item_name(gid)), gn, SEP.join(mat_parts)])
		if ready and player.copper >= copper:
			lines.append("　%s" % link("alchemy:%d" % i, "[兑换]"))
		else:
			lines.append("　%s" % dim("（材料或铜贝不足）"))
	lines.append(dim("（兑换来的龙泉水是强化装备的必需品，宝石则能嵌进带插槽的装备。）"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## 安德鲁（kind=trainer）：试炼任务（接受/进度/领奖，每日轮换；已学攻击术=完成态）
static func trainer_page(player: PlayerCore, npc: Dictionary, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header(String(npc.get("name", "安德鲁"))))
	for line: String in npc.get("lines", []):
		lines.append(esc(npc_line(line, player)))
	if notice != "":
		lines.append(esc(notice))
	if player.has_skill("attack"):
		lines.append("[color=#6fd66f]你已领会攻击术的窍门，这试炼对你而言已经完成。[/color]")
	else:
		var qa: Dictionary = player.quest_andrew
		var today := player.current_day()
		var state := String(qa.get("state", ""))
		var day := int(qa.get("day", -1))
		var goal := Rules.quest_andrew_kills()
		if state == "active" and day == today:
			var kills := int(qa.get("kills", 0))
			lines.append("今日试炼：击杀任意野外怪 %d/%d。" % [kills, goal])
			if kills >= goal:
				lines.append("安德鲁：干得漂亮！技能书和赏钱拿好。")
				lines.append("[center]%s[/center]" % link("quest_andrew:claim", "领取奖励"))
			else:
				lines.append(dim("（击败城外的野怪即可计数，地宫的杀戮不算。）"))
		elif state == "claimed" and day == today:
			lines.append("安德鲁：今天的赏钱你已经领过了，明天再来接试炼吧。")
		else:
			lines.append("安德鲁：今日试炼——击杀 %d 只野外野怪，赏你技能书一本，外加 %d 铜贝。接不接？" % [
				goal, Rules.quest_andrew_reward_copper()])
			lines.append("[center]%s[/center]" % link("quest_andrew:accept", "接下试炼"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## 西利亚（kind=siren）：海皇碎片任务 + 潜水指引
static func siren_page(player: PlayerCore, npc: Dictionary, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header(String(npc.get("name", "西利亚"))))
	for line: String in npc.get("lines", []):
		lines.append(esc(npc_line(line, player)))
	if notice != "":
		lines.append(esc(notice))
	var shards := player.count_stack(SIREN_SHARD_ID)
	var need := Rules.quest_siren_shards()
	if bool(player.quest_siren.get("claimed", false)):
		lines.append("西利亚：海皇的谢礼你已经带走了，愿海皇保佑你的航程。")
	elif shards >= need:
		var reward := Rules.quest_siren_reward()
		var reward_parts: Array[String] = []
		for id: String in reward:
			reward_parts.append("%s×%d" % [esc(player.item_name(id)), int(reward[id])])
		lines.append("西利亚：%d 片海皇碎片！快给我看看……这就是海皇宫殿的信物。说好的谢礼，一样不少：%s。" % [
			shards, "、".join(reward_parts)])
		lines.append("[center]%s[/center]" % link("quest_siren", "交付海皇碎片"))
	else:
		lines.append("西利亚：传说沉没的海皇宫殿藏着无价之宝，我只求一片宫殿的碎片。带 %d 片来，谢礼绝不亏待你。（%d/%d）" % [
			need, shards, need])
	lines.append("")
	lines.append(dim("（潜水地点：浅海与暗礁。水性要好，体力要足，深海偶尔还有海妖出没。）"))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


## 奥布帕斯（kind=riddle）：每日一谜（当日轮换取题），答对得铜贝，答错可再猜
static func riddle_day_index(day: int) -> int:
	var riddles := Rules.quest_riddles()
	if riddles.is_empty():
		return -1
	return ((day % riddles.size()) + riddles.size()) % riddles.size()


## 谜底选项：全部谜底去重（保持首次出现顺序），当日谜底必在其中
static func riddle_options() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in Rules.quest_riddles():
		var a := String(r.get("a", ""))
		if a != "" and not out.has(a):
			out.append(a)
	return out


static func riddle_page(player: PlayerCore, npc: Dictionary, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header(String(npc.get("name", "奥布帕斯"))))
	for line: String in npc.get("lines", []):
		lines.append(esc(npc_line(line, player)))
	var today := player.current_day()
	var idx := riddle_day_index(today)
	var riddles := Rules.quest_riddles()
	if idx < 0 or idx >= riddles.size():
		lines.append(dim("（谜语书缺了页，改日再猜。）"))
	else:
		var riddle: Dictionary = riddles[idx]
		if player.riddle_day == today:
			lines.append("今日之谜：%s" % esc(String(riddle.get("q", ""))))
			lines.append("奥布帕斯：哈哈，答案就是「%s」，你已猜中，赏钱已付。明日再来。" % esc(String(riddle.get("a", ""))))
		else:
			lines.append("奥布帕斯：猜中今日之谜，赏 %d 铜贝。答错不收钱，可以再猜。" % Rules.quest_riddle_reward_copper())
			lines.append("今日之谜：%s" % esc(String(riddle.get("q", ""))))
			var options := riddle_options()
			var parts: Array[String] = []
			for i in options.size():
				parts.append(link("riddle:%d" % i, options[i]))
			lines.append(SEP.join(parts))
	if notice != "":
		lines.append(esc(notice))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回"))
	return join_lines(lines)


# ---------- 改名 / 礼包 / 强化 / 宝石 ----------

## 改名页（契约 §5.8）：GameScreen 据 input_mode="rename" 显示输入行
static func rename_page(player: PlayerCore, error_msg: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header("改名卡"))
	lines.append("在上方输入框输入新昵称（12 字以内），点击确定。")
	if error_msg != "":
		lines.append("[color=red]%s[/color]" % esc(error_msg))
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("rename_ok", "确定改名"), link("back_game", "取消")])
	return join_lines(lines)


static func rename_result(player: PlayerCore) -> String:
	var lines: Array[String] = []
	lines.append(header("改名卡"))
	lines.append("改名成功！从现在起，请叫我「%s」。" % esc(player.nickname))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回游戏"))
	return join_lines(lines)


static func gift_result(player: PlayerCore, got: Array[String]) -> String:
	var lines: Array[String] = []
	lines.append(header("全服预约礼包"))
	for g in got:
		lines.append(esc(g))
	lines.append("")
	lines.append("[center]%s[/center]" % link("back_game", "返回游戏"))
	return join_lines(lines)


## 铁匠强化选装页（契约 §5：smith_enhance / smith_enhance:<idx>）
static func smith_enhance_page(player: PlayerCore, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header("铁匠铺 · 强化"))
	lines.append("铁匠：一瓶龙泉水淬火，%d 铜贝工钱，威力更上一层——强化过的装备就绑定喽，卖不得。" % Rules.smith_enhance_copper())
	lines.append("龙泉水：×%d  铜贝：%d" % [player.count_stack("longquanshui"), player.copper])
	if notice != "":
		lines.append(esc(notice))
	if player.equips.is_empty():
		lines.append(dim("你身上一件装备都没有。"))
	var can_pay := player.count_stack("longquanshui") > 0 and player.copper >= Rules.smith_enhance_copper()
	for i in player.equips.size():
		var inst := player.equips[i]
		var id := String(inst.get("id", ""))
		var enhance := maxi(int(inst.get("enhance", 0)), 0)
		if enhance >= Rules.smith_enhance_max():
			lines.append("▉%s%s 强化%d/%d  %s" % [
				quality_name(GameData.get_item(id), id), _equip_tag(i, player),
				enhance, Rules.smith_enhance_max(), dim("已到顶")])
		else:
			var action := link("smith_enhance:%d" % i, "[强化到+%d]" % (enhance + 1)) if can_pay else dim("（缺龙泉水或铜贝）")
			lines.append("▉%s%s 强化%d/%d  %s" % [
				quality_name(GameData.get_item(id), id), _equip_tag(i, player),
				enhance, Rules.smith_enhance_max(), action])
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("smith", "返回铁匠铺"), link("back_game", "返回游戏")])
	return join_lines(lines)


## 铁匠宝石页（契约 §5：两步交互 smith_gem → smith_gem:<装备> → smith_gem:<装备>:<宝石>）
static func smith_gem_page(player: PlayerCore, equip_idx: int, notice: String = "") -> String:
	var lines: Array[String] = []
	lines.append(header("铁匠铺 · 宝石镶嵌"))
	if notice != "":
		lines.append(esc(notice))
	if player.equips.is_empty():
		lines.append(dim("你身上一件装备都没有。"))
	elif equip_idx < 0 or equip_idx >= player.equips.size():
		# 第一步：选装备
		lines.append("铁匠：先把要镶宝石的装备挑出来（只有带插槽的装备吃得进宝石）。")
		for i in player.equips.size():
			var inst_sel: Dictionary = player.equips[i]
			var id_sel := String(inst_sel.get("id", ""))
			var def_sel := GameData.get_item(id_sel)
			var slots_sel := maxi(int(def_sel.get("slots", 0)), 0)
			var gems_sel: Array = inst_sel.get("gems", [])
			var slots_text := dim("无插槽")
			if slots_sel > 0:
				var full_mark := "" if gems_sel.size() < slots_sel else "（已满）"
				slots_text = "插槽%d/%d%s" % [gems_sel.size(), slots_sel, full_mark]
			lines.append("▉%s %s  %s" % [quality_name(def_sel, id_sel), _equip_tag(i, player), slots_text])
			if slots_sel > 0 and gems_sel.size() < slots_sel:
				lines.append("　%s" % link("smith_gem:%d" % i, "[选这件]"))
	else:
		# 第二步：选宝石
		var inst: Dictionary = player.equips[equip_idx]
		var id := String(inst.get("id", ""))
		var def := GameData.get_item(id)
		var slots := maxi(int(def.get("slots", 0)), 0)
		var gems: Array = inst.get("gems", [])
		lines.append("目标：%s %s（插槽 %d/%d）" % [
			quality_name(def, id), _equip_tag(equip_idx, player), gems.size(), slots])
		for g in gems:
			var gid := String(g)
			lines.append("　已镶：%s" % quality_name(GameData.get_item(gid), gid))
		var any_gem := false
		for gid: String in player.bag:
			var gdef := GameData.get_item(gid)
			if String(gdef.get("type", "")) != "gem" or int(player.bag[gid]) <= 0:
				continue
			any_gem = true
			var bonus: Dictionary = gdef.get("bonus", {})
			var bparts: Array[String] = []
			for k: String in bonus:
				bparts.append("%s+%d" % [String(GEM_BONUS_LABELS.get(k, k)), int(bonus[k])])
			if gems.size() < slots:
				lines.append("▉%s ×%d（%s）  %s" % [
					quality_name(gdef, gid), int(player.bag[gid]), SEP.join(bparts),
					link("smith_gem:%d:%s" % [equip_idx, gid], "[镶嵌]")])
			else:
				lines.append("▉%s ×%d（%s）  %s" % [
					quality_name(gdef, gid), int(player.bag[gid]), SEP.join(bparts), dim("插槽已满")])
		if not any_gem:
			lines.append(dim("包里没有宝石。矿洞的怪掉宝石，博士的助手也能炼出来。"))
		lines.append("[center]%s[/center]" % link("smith_gem", "重选装备"))
	lines.append("")
	lines.append("[center]%s   %s[/center]" % [link("smith", "返回铁匠铺"), link("back_game", "返回游戏")])
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
