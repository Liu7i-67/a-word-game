class_name Life
## 生活玩法引擎（契约 plan-v2 §4.3 + §5 裁决）：打坐/钓鱼/潜水，纯静态无状态。
## 数值全部走 Rules getter（config life 节，缺省兜底）；随机一律走 player.rng，
## 保证 self_test 定种子可复现。结果统一 Dictionary{ok, msg, ...} 由 router 渲染；
## dive 抽中 monster: 前缀只返回 monster_id，战斗由 router 起 CombatEngine。

const MEDITATE_TOOL_ID := "yeqiu_caoren"
const BAIT_ID := "xiaoyu_huoer"


## 打坐（§5.2）：需持有野球草人 + 等级达标 + meditate_stamina 体力；
## exp = level × meditate_exp_per_level × exp_mult，即时结算可连点。返回 {ok, msg, exp}
static func meditate(player: PlayerCore) -> Dictionary:
	GameData.ensure_loaded()
	if player.count_stack(MEDITATE_TOOL_ID) <= 0:
		return {"ok": false, "msg": "你还没学会打坐——听说野球草人里藏着诀窍。", "exp": 0}
	var eff: Dictionary = GameData.get_item(MEDITATE_TOOL_ID).get("effect", {})
	var need_level := maxi(int(eff.get("req_level", 10)), 1)
	if player.level < need_level:
		return {"ok": false, "msg": "修为尚浅，%d 级才能安心打坐。" % need_level, "exp": 0}
	if not player.spend_stamina(Rules.life_meditate_stamina()):
		return {"ok": false, "msg": "体力不足（打坐要 %d 点），先吃点东西吧。" % Rules.life_meditate_stamina(), "exp": 0}
	var gained := maxi(int(round(float(player.level) * float(Rules.life_meditate_exp_per_level()) * player.exp_mult())), 0)
	player.add_exp(gained)
	return {"ok": true, "msg": "你盘膝而坐，气沉丹田，只觉精进不已。", "exp": gained}


## 钓鱼（§5.3）：扣 fish_stamina 体力；use_bait 时先扣 1 条小鱼活饵并改抽 bait 表。
## 返回 {ok, msg, item_id}（渔获已入包）
static func fish(player: PlayerCore, use_bait: bool) -> Dictionary:
	GameData.ensure_loaded()
	if use_bait and player.count_stack(BAIT_ID) <= 0:
		return {"ok": false, "msg": "活饵用完了，空钩钓不上大家伙。", "item_id": ""}
	if not player.spend_stamina(Rules.life_fish_stamina()):
		return {"ok": false, "msg": "体力不足（钓鱼要 %d 点），歇会再来。" % Rules.life_fish_stamina(), "item_id": ""}
	if use_bait:
		player.remove_stack(BAIT_ID, 1)
	var item_id := _draw_weighted(player, Rules.life_fish_table_bait() if use_bait else Rules.life_fish_table())
	if item_id == "":
		return {"ok": true, "msg": "浮漂动了动，什么也没钓上来。", "item_id": ""}
	if not player.add_stack(item_id, 1):
		return {"ok": false, "msg": "鱼篓塞不下了，只好把%s放生。" % player.item_name(item_id), "item_id": ""}
	return {"ok": true, "msg": "你钓起了一条%s！" % player.item_name(item_id), "item_id": item_id}


## 潜水（§5.4）：扣 dive_stamina 体力抽 dive_table；
## nothing=安慰文案；monster: 前缀=返回 monster_id 交 router 起 CombatEngine。
## 返回 {ok, msg, item_id, monster_id}
static func dive(player: PlayerCore) -> Dictionary:
	GameData.ensure_loaded()
	if not player.spend_stamina(Rules.life_dive_stamina()):
		return {"ok": false, "msg": "体力不足（潜水要 %d 点），可别在水里抽筋。" % Rules.life_dive_stamina(), "item_id": "", "monster_id": ""}
	var roll := _draw_weighted(player, Rules.life_dive_table())
	if roll == "nothing":
		return {"ok": true, "msg": "你潜入海底，除了一串气泡，什么也没捞到。", "item_id": "", "monster_id": ""}
	if roll.begins_with("monster:"):
		return {"ok": true, "msg": "水下暗流涌动，一团黑影朝你逼近——", "item_id": "", "monster_id": roll.trim_prefix("monster:")}
	if roll == "":
		return {"ok": true, "msg": "你空手而归，海水打湿了衣角。", "item_id": "", "monster_id": ""}
	if not player.add_stack(roll, 1):
		return {"ok": false, "msg": "怀里塞不下捞到的%s，只好松手。" % player.item_name(roll), "item_id": "", "monster_id": ""}
	return {"ok": true, "msg": "你从海底捞起了%s！" % player.item_name(roll), "item_id": roll, "monster_id": ""}


## 旅店住店（契约 docs/sail-region-spec.md §1.7）：扣 cost 铜贝；成功则生活体力回满、
## HP 回满（heal 内部 hp_changed 通知页面刷新）；余额不足给契约语气文案。返回 {ok, msg}
static func inn_rest(player: PlayerCore, cost: int) -> Dictionary:
	if not player.spend_copper(cost):
		return {"ok": false, "msg": "房费 %d 铜贝都拿不出来，老板娘把钥匙又挂了回去。" % cost}
	player.stamina = player.max_stamina()
	player.heal(player.max_hp())
	return {"ok": true, "msg": "你开了间房，美美睡了一觉。生活体力和体力全都回满了！"}


## 按权重表抽一个 id（w=权重%，契约要求各表合计=100；此处按总和归一容错）
static func _draw_weighted(player: PlayerCore, table: Array) -> String:
	var total := 0
	for e: Dictionary in table:
		total += maxi(int(e.get("w", 0)), 0)
	if total <= 0:
		return ""
	var roll := player.rng.randi_range(0, total - 1)
	for e: Dictionary in table:
		roll -= maxi(int(e.get("w", 0)), 0)
		if roll < 0:
			return String(e.get("id", ""))
	return ""
