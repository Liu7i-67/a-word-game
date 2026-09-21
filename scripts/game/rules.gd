class_name Rules
## 数值公式集中地：公式在这里，数值在 data/config.json（来源✅/🔍标注见该文件 _doc）。

static func section(name: String) -> Dictionary:
	GameData.ensure_loaded()
	return GameData.config.get(name, {})


## 升级曲线：1 级 500（文档✅），此后每级线性 +exp_step（🔍）
static func exp_to_next(level: int) -> int:
	var g := section("growth")
	return int(g.get("exp_base", 500)) + int(g.get("exp_step", 500)) * maxi(level - 1, 0)


static func max_hp(level: int) -> int:
	var g := section("growth")
	return int(g.get("hp_base", 100)) + int(g.get("hp_per_level", 20)) * maxi(level - 1, 0)


## 裸身攻击区间（不含武器加成）
static func base_atk(level: int) -> Vector2i:
	var g := section("growth")
	var lo := int(g.get("atk_min_base", 5)) + int(g.get("atk_min_per_level", 2)) * maxi(level - 1, 0)
	var hi := int(g.get("atk_max_base", 15)) + int(g.get("atk_max_per_level", 5)) * maxi(level - 1, 0)
	return Vector2i(lo, hi)


static func base_def(level: int) -> int:
	var g := section("growth")
	return int(g.get("def_base", 0)) + int(g.get("def_per_level", 1)) * maxi(level - 1, 0)


static func weight_cap(level: int) -> int:
	var g := section("growth")
	return int(g.get("weight_base", 100)) + int(g.get("weight_per_level", 10)) * maxi(level - 1, 0)


static func copper_per_silver() -> int:
	return int(section("economy").get("copper_per_silver", 100))


static func welfare_copper() -> int:
	return int(section("economy").get("welfare_copper", 10000))


static func heal_amount() -> int:
	return int(section("economy").get("heal_amount", 50))


static func confess_reduce() -> int:
	return int(section("economy").get("confess_reduce", 10))


static func casino_bet() -> int:
	return int(section("economy").get("casino_bet", 200))


static func casino_win() -> int:
	return int(section("economy").get("casino_win", 1000))


static func sell_price(buy_price: int) -> int:
	var pct := int(section("economy").get("sell_ratio_pct", 50))
	return maxi(buy_price * pct / 100, 1)


static func retreat_cost(enemy_level: int) -> int:
	return int(section("combat").get("retreat_cost_per_level", 10)) * maxi(enemy_level, 0)


## 战败丢失铜贝：按随身铜贝的百分比（🔍，原版数值锁在字节码）
static func death_loss(copper_carried: int) -> int:
	var c := section("combat")
	var lost := copper_carried * int(c.get("death_loss_ratio_pct", 10)) / 100
	return clampi(lost, int(c.get("death_loss_min", 1)), int(c.get("death_loss_max", 5000)))


static func revive_hp(maximum: int) -> int:
	return maxi(int(maximum * int(section("combat").get("revive_ratio_pct", 50)) / 100), 1)


static func revive_scene() -> String:
	return String(section("combat").get("revive_scene", "gaautong"))


## 自动战斗体力终止阈值（百分比）：低于该比例自动停止/禁止启动（🔍交互优化）
static func auto_stop_hp_pct() -> int:
	return maxi(int(section("combat").get("auto_stop_hp_pct", 30)), 0)


static func teleport_cost_silver() -> int:
	return int(section("teleport").get("cost_silver", 10))


## 传送实际扣费（契约 trade-spec §6：文案仍写「10银」，扣款走 cost_copper 自动折兑）
static func teleport_cost_copper() -> int:
	return int(section("teleport").get("cost_copper", 1000))


## 出海船费（契约 docs/sail-region-spec.md §1.6，economy.sail_cost）
static func sail_cost() -> int:
	return maxi(int(section("economy").get("sail_cost", 1000)), 0)


## 旅店住店费（契约 docs/sail-region-spec.md §1.7，economy.inn_cost）
static func inn_cost() -> int:
	return maxi(int(section("economy").get("inn_cost", 100)), 0)


## 酒保打听价（契约 trade-spec §5）
static func rumor_cost() -> int:
	return int(section("economy").get("rumor_cost", 20))


## 装备回收比例 pct（契约 trade-spec §7，默认 40%）
static func equip_sell_ratio_pct() -> int:
	return int(section("economy").get("equip_sell_ratio_pct", 40))


## 装备回收价 = round(基准价值 × 回收比例)
static func equip_sell_price(base_price: int) -> int:
	return int(round(float(maxi(base_price, 0)) * float(equip_sell_ratio_pct()) / 100.0))


static func click_cooldown_ms() -> int:
	return int(section("ui").get("click_cooldown_ms", 250))


## 自动战斗每步间隔（毫秒）：模拟人手速，逐步驱动「攻击/继续/返回」（🔍交互优化）
static func auto_tick_ms() -> int:
	return maxi(int(section("ui").get("auto_tick_ms", 450)), 50)


static func link_color() -> String:
	return String(section("ui").get("link_color", "#66b3ff"))


## 修理价：耐久缺口 × 单点修理费（扩展契约 §3.4）
static func repair_cost(missing: int) -> int:
	return maxi(missing, 0) * int(section("economy").get("repair_cost_per_point", 2))


## ---------- 威尼斯地宫（扩展契约 §4.5，数值全在 config.combat） ----------

## 进入条件（探险官台词✅：5 级以上、每日一次——本版仅校验等级）
static func dungeon_level_range() -> Vector2i:
	var c := section("combat")
	return Vector2i(int(c.get("dungeon_level_min", 5)), int(c.get("dungeon_level_max", 15)))


static func dungeon_scene() -> String:
	return String(section("combat").get("dungeon_scene", "digung"))


static func dungeon_exit_scene() -> String:
	return String(section("combat").get("dungeon_exit_scene", "baksingmun"))


static func dungeon_monster() -> String:
	return String(section("combat").get("dungeon_monster", "qiang_jie_zhe"))


static func dungeon_kill_goal() -> int:
	return int(section("combat").get("dungeon_kill_goal", 40))


static func dungeon_time_limit_sec() -> int:
	return int(section("combat").get("dungeon_time_limit_sec", 3000))


static func dungeon_reward_copper() -> int:
	return int(section("combat").get("dungeon_reward_copper", 20000))


static func dungeon_reward_gold() -> int:
	return int(section("combat").get("dungeon_reward_gold", 1))


## ---------- GM 彩蛋（福利官暗号，数值在 config.gm） ----------

static func gm_password() -> String:
	return String(section("gm").get("password", "676767"))


static func gm_exp_pill() -> String:
	return String(section("gm").get("exp_pill", ""))


static func gm_exp_pill_count() -> int:
	return maxi(int(section("gm").get("exp_pill_count", 0)), 0)


static func gm_knife() -> String:
	return String(section("gm").get("knife", ""))


## ---------- 检查更新（GitHub Release，数值在 config.update） ----------

static func github_repo() -> String:
	return String(section("update").get("repo", ""))


## 远端版本是否新于本地版本：按 major.minor.patch 数值逐段比较，缺省段按 0
static func version_newer(remote: String, local: String) -> bool:
	var r := _version_tuple(remote)
	var l := _version_tuple(local)
	for i in 3:
		if r[i] != l[i]:
			return r[i] > l[i]
	return false


static func _version_tuple(v: String) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	var parts := v.strip_edges().trim_prefix("v").trim_prefix("V").split(".")
	for i in mini(parts.size(), 3):
		out[i] = maxi(String(parts[i]).to_int(), 0)
	return out


## ---------- 生活系统（契约 plan-v2 §2.4 life 节，缺省兜底与 config 同值） ----------

static func life_stamina_max() -> int:
	return maxi(int(section("life").get("stamina_max", 1000)), 1)


static func life_stamina_per_level() -> int:
	return maxi(int(section("life").get("stamina_per_level", 50)), 0)


static func life_meditate_stamina() -> int:
	return maxi(int(section("life").get("meditate_stamina", 100)), 0)


static func life_meditate_exp_per_level() -> int:
	return maxi(int(section("life").get("meditate_exp_per_level", 20)), 0)


static func life_fish_stamina() -> int:
	return maxi(int(section("life").get("fish_stamina", 30)), 0)


static func life_dive_stamina() -> int:
	return maxi(int(section("life").get("dive_stamina", 40)), 0)


static func life_farm_stamina() -> int:
	return maxi(int(section("life").get("farm_stamina", 20)), 0)


static func life_farm_plots() -> int:
	return maxi(int(section("life").get("farm_plots", 4)), 0)


static func life_farm_grow_sec() -> int:
	return maxi(int(section("life").get("farm_grow_sec", 600)), 0)


static func life_farm_harvest_count() -> int:
	return maxi(int(section("life").get("farm_harvest_count", 3)), 0)


## 体力低于该百分比时自动吃奶瓶/体力宝（🔍原版文案）
static func life_auto_stamina_pct() -> int:
	return clampi(int(section("life").get("auto_stamina_pct", 50)), 0, 100)


## 体力宝限持个数（🔍原版文案：每人限 2 个，buy/gift 入包时校验）
static func life_tili_bao_limit() -> int:
	return maxi(int(section("life").get("tili_bao_limit", 2)), 0)


static func _life_array(key: String, fallback: Array) -> Array:
	var v: Variant = section("life").get(key, fallback)
	return (v as Array).duplicate(true) if v is Array else fallback.duplicate(true)


static func life_fish_scenes() -> Array:
	return _life_array("fish_scenes", ["haitan", "tsienhoi", "ngoanzo", "maatau"])


static func life_dive_scenes() -> Array:
	return _life_array("dive_scenes", ["tsienhoi", "ngoanzo"])


static func life_fish_table() -> Array:
	return _life_array("fish_table", [
		{"id": "xiaoyu", "w": 45}, {"id": "daiyu", "w": 30}, {"id": "zhangyu", "w": 17},
		{"id": "jinqiangyu", "w": 6}, {"id": "xiaoyu_huoer", "w": 2},
	])


static func life_fish_table_bait() -> Array:
	return _life_array("fish_table_bait", [
		{"id": "daiyu", "w": 30}, {"id": "zhangyu", "w": 30}, {"id": "jinqiangyu", "w": 28},
		{"id": "xiaoyu_huoer", "w": 10}, {"id": "zhenzhu", "w": 2},
	])


static func life_dive_table() -> Array:
	return _life_array("dive_table", [
		{"id": "nothing", "w": 50}, {"id": "xiaoyu", "w": 20}, {"id": "zhenzhu", "w": 20},
		{"id": "monster:hai_yao", "w": 7}, {"id": "haihuang_suipian", "w": 3},
	])


## ---------- 铁匠强化/炼金（契约 plan-v2 §2.4 smith 节） ----------

static func smith_enhance_max() -> int:
	return maxi(int(section("smith").get("enhance_max", 7)), 0)


static func smith_enhance_copper() -> int:
	return maxi(int(section("smith").get("enhance_copper", 200)), 0)


## 每级强化攻击/防御加成百分比（契约 §4.1 锁定值，不进 config）
static func smith_enhance_pct_per() -> int:
	return 5


static func smith_alchemy() -> Array:
	return _life_array_alike("smith", "alchemy", [])


## ---------- 任务链/谜语（契约 plan-v2 §2.4 quest 节） ----------

static func quest_andrew_kills() -> int:
	return maxi(int(section("quest").get("andrew_kills", 10)), 0)


static func quest_andrew_reward_copper() -> int:
	return maxi(int(section("quest").get("andrew_reward_copper", 1000)), 0)


static func quest_siren_shards() -> int:
	return maxi(int(section("quest").get("siren_shards", 3)), 0)


static func quest_siren_reward() -> Dictionary:
	var v: Variant = section("quest").get("siren_reward", {"longquanshui": 3, "shuangbei_jingyanka": 1})
	return (v as Dictionary).duplicate(true) if v is Dictionary else {"longquanshui": 3, "shuangbei_jingyanka": 1}


static func quest_riddle_reward_copper() -> int:
	return maxi(int(section("quest").get("riddle_reward_copper", 500)), 0)


## 谜语库（第 5 条由 D1 重写，兜底只保留可确证的 4 条）
static func quest_riddles() -> Array:
	return _life_array_alike("quest", "riddles", [
		{"q": "有头无颈，有眼无眉，无脚能行，有翅难飞。（打一动物）", "a": "鱼"},
		{"q": "白天草里住，晚上空中游，金光闪闪动，小尾灯一盏。（打一昆虫）", "a": "萤火虫"},
		{"q": "小小诸葛亮，独坐军中帐，摆下八卦阵，专捉飞来将。（打一动物）", "a": "蜘蛛"},
		{"q": "一物生来强，每天织网忙，织完静静坐，专等蚊虫撞。（打一动物）", "a": "蜘蛛"},
	])


static func _life_array_alike(section_name: String, key: String, fallback: Array) -> Array:
	var v: Variant = section(section_name).get(key, fallback)
	return (v as Array).duplicate(true) if v is Array else fallback.duplicate(true)


## ---------- 战斗扩展（契约 plan-v2 §2.4 combat 节新增字段） ----------

## 士气上限（连胜每场 +1 攻击%，封顶）
static func combat_momentum_max() -> int:
	return maxi(int(section("combat").get("momentum_max", 10)), 0)


static func combat_momentum_atk_pct_per() -> int:
	return maxi(int(section("combat").get("momentum_atk_pct_per", 1)), 0)


static func combat_dodge_pct_per_agi() -> int:
	return maxi(int(section("combat").get("dodge_pct_per_agi", 1)), 0)


## 闪避率上限（%）：敏捷减伤封顶
static func combat_dodge_pct_max() -> int:
	return clampi(int(section("combat").get("dodge_pct_max", 20)), 0, 100)


static func combat_lucky_pct_per() -> int:
	return maxi(int(section("combat").get("lucky_pct_per", 1)), 0)


## 幸运一击伤害倍率（%）
static func combat_lucky_mult_pct() -> int:
	return maxi(int(section("combat").get("lucky_mult_pct", 200)), 100)


## 攻击术体力消耗
static func combat_skill_stamina() -> int:
	return maxi(int(section("combat").get("skill_stamina", 50)), 0)


## 攻击术伤害倍率（%）
static func combat_skill_mult_pct() -> int:
	return maxi(int(section("combat").get("skill_mult_pct", 150)), 100)
