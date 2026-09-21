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


static func teleport_cost_silver() -> int:
	return int(section("teleport").get("cost_silver", 10))


static func click_cooldown_ms() -> int:
	return int(section("ui").get("click_cooldown_ms", 250))


static func link_color() -> String:
	return String(section("ui").get("link_color", "#66b3ff"))


## 威尼斯地宫进入条件（探险官台词✅：5 级以上、6 人同行、每日一次——本版仅校验等级）
static func dungeon_level_range() -> Vector2i:
	return Vector2i(5, 15)
