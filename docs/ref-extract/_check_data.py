# -*- coding: utf-8 -*-
"""D1 数据层自查脚本（内容契约 plan-v2 §2 校验，E2 可复用）。

用法：python docs/ref-extract/_check_data.py
校验：四文件 JSON 可解析(UTF-8 无 BOM)；items/monsters/scenes id 唯一；场景 exits 双向且指向存在；
场景 monsters/npcs 引用存在；npc kind 白名单；drop_item/drop_equip/forge 材料/gift contents/
alchemy give&get/quest/fish&dive 表 id 存在(nothing 与 monster: 前缀合法)；权重表合计 100；
equip armor 有 def、gem 有 bonus；契约锁定 id 全部在位；不在售物品 price=0。
"""
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

def half_up(x):
    """GDScript round() 语义：半值远离零（现有表 L9/L11/L13 def 为证），非 Python 银行家舍入。"""
    return int(x + 0.5)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DATA = os.path.join(ROOT, "data")

errors = []
def check(cond, msg):
    if not cond:
        errors.append(msg)

def load_raw(name):
    path = os.path.join(DATA, name)
    with open(path, "rb") as f:
        raw = f.read()
    check(not raw.startswith(b"\xef\xbb\xbf"), f"{name}: 含 UTF-8 BOM")
    return json.loads(raw.decode("utf-8"))

def dup_keys(name, indent):
    """JSON 对象重复键会被静默覆盖，用文本级正则检测。"""
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        text = f.read()
    keys = re.findall(r"^ {%d}\"([^\"]+)\":" % indent, text, re.M)
    seen, dups = set(), []
    for k in keys:
        if k in seen and k not in dups:
            dups.append(k)
        seen.add(k)
    return dups

items_doc = load_raw("items.json")
monsters_doc = load_raw("monsters.json")
scenes_doc = load_raw("scenes.json")
config = load_raw("config.json")

items = items_doc["items"]
monsters = monsters_doc["monsters"]
scenes = {s["id"]: s for s in scenes_doc["scenes"]}

# ---- 1/2. id 唯一 ----
for name, indent in (("items.json", 4), ("monsters.json", 4)):
    for k in dup_keys(name, indent):
        errors.append(f"{name}: 重复 id {k}")
scene_ids = re.findall(r'^      "id": "([^"]+)",', open(os.path.join(DATA, "scenes.json"), encoding="utf-8").read(), re.M)
for k in set(i for i in scene_ids if scene_ids.count(i) > 1):
    errors.append(f"scenes.json: 重复场景 id {k}")
check(len(scenes) == len(scenes_doc["scenes"]), "scenes.json: 场景 id 去重后数量不一致")

# ---- 3. exits 双向且指向存在 ----
for s in scenes_doc["scenes"]:
    for ex in s.get("exits", []):
        to = ex.get("to")
        check(bool(to) and to in scenes, f"场景 {s['id']} 出口 {ex} 指向不存在的场景")
        if to in scenes:
            backs = [e.get("to") for e in scenes[to].get("exits", [])]
            check(s["id"] in backs, f"出口非双向: {s['id']} -> {to} 无回程出口")

# ---- 4/5. 场景 monsters/npcs 引用与 kind 白名单 ----
BASE_KINDS = {"flavor", "welfare", "church", "bank", "casino", "market", "teleport", "sail",
              "dungeon", "shop", "smith", "trade_market", "tavern_rumor", "dungeon_keeper"}
NEW_KINDS = {"tavern", "circus", "alchemist", "trainer", "siren", "riddle"}
KINDS = BASE_KINDS | NEW_KINDS
for s in scenes_doc["scenes"]:
    for m in s.get("monsters", []):
        check(m.get("id") in monsters, f"场景 {s['id']} 挂不存在的怪 {m.get('id')}")
        check(isinstance(m.get("count"), int) and m["count"] > 0, f"场景 {s['id']} 怪 {m.get('id')} count 非法")
    for n in s.get("npcs", []):
        check(n.get("id") and n.get("name") and n.get("kind"), f"场景 {s['id']} NPC 缺 id/name/kind")
        check(n.get("kind") in KINDS, f"场景 {s['id']} NPC {n.get('id')} kind={n.get('kind')} 不在白名单")
        if n.get("kind") == "flavor":
            check(n.get("lines"), f"场景 {s['id']} flavor NPC {n.get('id')} 缺 lines")

# ---- 6. 引用存在性 ----
def item_ref_ok(iid):
    if iid in items:
        return True
    if iid == "nothing":
        return True
    if iid.startswith("monster:"):
        return iid[len("monster:"):] in monsters
    return False

for mid, m in monsters.items():
    di = m.get("drop_item")
    check(not di or di in items, f"怪 {mid} drop_item 引用不存在的物品 {di}")
    de = m.get("drop_equip")
    if de:
        deid = de.get("id")
        check(deid in items, f"怪 {mid} drop_equip 引用不存在的装备 {deid}")
        check(items.get(deid, {}).get("type") == "equip", f"怪 {mid} drop_equip {deid} 不是 equip 类型")
        check(isinstance(de.get("rate"), (int, float)) and 0 < de["rate"] <= 100, f"怪 {mid} drop_equip rate 非法")
    check(isinstance(m.get("drop_rate", 0), int), f"怪 {mid} drop_rate 非法")

for iid, it in items.items():
    t = it.get("type")
    if t == "equip" and it.get("forge"):
        for mat in it["forge"].get("materials", {}):
            check(mat in items, f"装备 {iid} forge 材料引用不存在的物品 {mat}")
    if t == "item":
        eff = it.get("effect", {})
        if eff.get("kind") == "gift":
            for cid in eff.get("contents", {}):
                if cid != "copper":
                    check(cid in items, f"礼包 {iid} contents 引用不存在的物品 {cid}")
    if t == "equip" and it.get("slot") == "armor":
        check(isinstance(it.get("def"), int) and it["def"] > 0, f"armor {iid} 缺 def")
    if t == "gem":
        check(bool(it.get("bonus")), f"gem {iid} 缺 bonus")
        check(all(k in ("atk", "def", "agi", "hp") for k in it.get("bonus", {})), f"gem {iid} bonus 键非法")
    if t == "equip":
        check(it.get("quality") in ("普通", "精良", "稀有", "完美", "史诗", "传奇"),
              f"equip {iid} quality={it.get('quality')} 不在 6 档之内")
        fg = it.get("forge")
        if fg:
            check(it.get("price", 0) > 0, f"equip {iid} 有 forge 但 price<=0(回炉基准缺失)")
            check(isinstance(fg.get("copper"), int) and fg["copper"] > 0, f"equip {iid} forge 缺铜贝价")
            check(iid in items and all(m in items for m in fg.get("materials", {})),
                  f"equip {iid} forge 材料引用不存在")

smith = config.get("smith", {})
for rec in smith.get("alchemy", []):
    for gid in rec.get("give", {}):
        if gid != "copper":
            check(gid in items, f"alchemy give 引用不存在的物品 {gid}")
    check(rec.get("get", {}).get("id") in items, f"alchemy get 引用不存在的物品 {rec.get('get', {}).get('id')}")

quest = config.get("quest", {})
for iid in quest.get("siren_reward", {}):
    check(iid in items, f"quest.siren_reward 引用不存在的物品 {iid}")

# ---- 7. fish/dive 权重表合计=100 且 id 合法 ----
life = config.get("life", {})
for tbl in ("fish_table", "fish_table_bait", "dive_table"):
    entries = life.get(tbl, [])
    total = sum(e.get("w", 0) for e in entries)
    check(total == 100, f"life.{tbl} 权重合计 {total} != 100")
    for e in entries:
        check(item_ref_ok(e.get("id", "")), f"life.{tbl} 引用非法 id {e.get('id')}")
for sid in life.get("fish_scenes", []) + life.get("dive_scenes", []):
    check(sid in scenes, f"life 场景清单引用不存在的场景 {sid}")

# ---- 8. 契约锁定条目在位 ----
NEW_ITEMS = ["changjian", "duanchui", "piyaodai", "cuzhitongkui", "niurouxianbing", "quqibing",
             "tili_bao", "huolong_tangyuan", "naiping", "shuangbei_jingyanka", "huanyuan_ka",
             "qiankun_dai", "yeqiu_caoren", "gaiming_ka", "jineng_shu", "longquanshui",
             "mucao_zhongzi", "xiaoyu_huoer", "yinlu_feng", "yufu_libao",
             "haihuang_suipian", "hongbaoshi", "lanbaoshi", "lvbaoshi", "zibaoshi",
             "xiaoyu", "daiyu", "zhangyu", "jinqiangyu", "mucao",
             "xuantiezhongjian", "xuantiejia", "anlinjuren", "lingzhuzhiren"]
for iid in NEW_ITEMS:
    check(iid in items, f"缺少契约物品 {iid}")
NEW_MONSTERS = ["kuangshu", "duwu_bianfu", "feixu_kulou", "anying_wuling",
                "baolei_shouwei", "hei_an_qishi", "baolei_lingzhu"]
for mid in NEW_MONSTERS:
    check(mid in monsters, f"缺少契约怪物 {mid}")
FORMULA = {"hp": lambda L: half_up(40 * L ** 1.2), "atk": lambda L: [3 + 2 * L, 8 + 3 * L],
           "def": lambda L: half_up(5 + 1.5 * L), "exp": lambda L: [round(0.8 * L) + 1, 4 * L + 5],
           "copper": lambda L: [5 * L, 15 * L + 10]}
for mid in NEW_MONSTERS:
    if mid in monsters:
        m, L = monsters[mid], monsters[mid]["level"]
        for k, fn in FORMULA.items():
            check(m[k] == fn(L), f"怪 {mid}.{k}={m[k]} 偏离生成公式 {fn(L)}")
for sid in ("biltou", "feizoi", "kuongdung"):
    check(sid in scenes, f"缺少契约场景 {sid}")

TAVERN_NPCS = {"zaugun": ["boss", "deluoxi", "andedalu", "lusi", "xiliya", "aobupasi"],
               "soenmon": ["zhushou"]}
for sid, want in TAVERN_NPCS.items():
    got = [n["id"] for n in scenes.get(sid, {}).get("npcs", [])]
    for nid in want:
        check(nid in got, f"场景 {sid} 缺少 NPC {nid}")

check(monsters.get("du_she", {}).get("poison") == 8, "du_she 缺 poison:8")
check(monsters.get("duwu_bianfu", {}).get("poison") == 10, "duwu_bianfu 缺 poison:10")

NOT_FOR_SALE = ["tili_bao", "shuangbei_jingyanka", "huanyuan_ka", "jineng_shu", "longquanshui", "yufu_libao", "haihuang_suipian"]
for iid in NOT_FOR_SALE:
    it = items.get(iid, {})
    check(it.get("price", 0) == 0, f"{iid} price 应为 0(不在售)")

# 契约锁定数值抽查
check(len(quest.get("riddles", [])) == 5, "quest.riddles 应有 5 条")
check(all("couch" not in r.get("q", "") for r in quest.get("riddles", [])), "riddles 含坏占位 couch")
check("couch" not in json.dumps(config, ensure_ascii=False), "config 残留坏占位 couch")
for key, val in {"momentum_max": 10, "momentum_atk_pct_per": 1, "dodge_pct_per_agi": 1, "dodge_pct_max": 20,
                 "lucky_pct_per": 1, "lucky_mult_pct": 200, "skill_stamina": 50, "skill_mult_pct": 150}.items():
    check(config.get("combat", {}).get(key) == val, f"combat.{key} 应为 {val}")
for key, val in {"stamina_max": 1000, "stamina_per_level": 50, "meditate_stamina": 100,
                 "meditate_exp_per_level": 20, "fish_stamina": 30, "dive_stamina": 40,
                 "farm_stamina": 20, "farm_plots": 4, "farm_grow_sec": 600,
                 "farm_harvest_count": 3, "auto_stamina_pct": 50, "tili_bao_limit": 2}.items():
    check(life.get(key) == val, f"life.{key} 应为 {val}")
check(smith.get("enhance_max") == 7 and smith.get("enhance_copper") == 200, "smith.enhance_* 应为 7/200")
check(quest.get("andrew_kills") == 10 and quest.get("siren_shards") == 3
      and quest.get("riddle_reward_copper") == 500, "quest 数值与契约不符")
check(quest.get("andrew_reward_copper") == 1000, "quest.andrew_reward_copper 应为 1000")

# 新场景怪挂载与接线抽查
for sid, want in (("kuongdung", {"kuangshu", "duwu_bianfu"}),
                  ("feizoi", {"feixu_kulou", "anying_wuling"}),
                  ("biltou", {"baolei_shouwei", "hei_an_qishi", "baolei_lingzhu"})):
    got = {m["id"] for m in scenes.get(sid, {}).get("monsters", [])}
    check(got == want, f"场景 {sid} 怪挂载 {got} != {want}")
check({"kuongdung"} <= {e.get("to") for e in scenes.get("kuaangsan", {}).get("exits", [])}, "矿山未接矿洞")
check({"feizoi"} <= {e.get("to") for e in scenes.get("hongjoe", {}).get("exits", [])}, "荒野未接废墟")
check({"biltou"} <= {e.get("to") for e in scenes.get("feizoi", {}).get("exits", [])}, "废墟未接堡垒")

# ---- 汇总 ----
counts = (f"items={len(items)}(+{len(NEW_ITEMS)}) monsters={len(monsters)}(+{len(NEW_MONSTERS)}) "
          f"scenes={len(scenes_doc['scenes'])}(+3)")
if errors:
    print(f"FAIL {counts}")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
print(f"PASS {counts}")
print("OK: JSON 可解析(UTF-8 无 BOM) / id 唯一 / exits 双向且指向存在 / 怪与NPC引用存在 / kind 白名单 /")
print("    drop·forge·gift·alchemy·quest·fish·dive 引用全部存在 / 三张权重表合计=100 / armor有def·gem有bonus /")
print("    契约锁定 id 与数值全部在位 / 不在售物品 price=0")
