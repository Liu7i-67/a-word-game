# 06 - 数据库结构（db.sqlite3，SQLite，20 张表）

提取方式：`python -c` + sqlite3 模块读取 `sqlite_master`。

## 1. 表清单与行数

| 表 | 行数 | 用途 |
|---|---|---|
| map_map | 1 | 地图（威尼斯） |
| monster_monster | **0** | 怪物（从未录入） |
| npc_npc | 7 | NPC |
| stuff_stuff | 20 | 物品主表 |
| stuff_weapon | 2 | 武器子表（多表继承，stuff_ptr_id → stuff_stuff.id） |
| stuff_armor | 2 | 护甲子表 |
| stuff_consumable | 15 | 消耗品子表（无额外字段） |
| player_user | 2 | 玩家（test, test2；曾有 yorkzz 被删） |
| player_playerstatus | 2 | 玩家状态 |
| player_playerstuff | 0 | 背包（玩家×物品×数量） |
| player_playerequipment | 0 | 装备栏（玩家×物品） |
| _npc_npc_old_20230311 | 0 | NPC 旧表备份（无 city 字段） |
| auth_user / auth_group / auth_permission / auth_* | 1/0/72/0 | Django 内置（1 个超管） |
| django_content_type | 18 | 含 18 个模型注册 |
| django_admin_log | 49 | 后台操作日志 |
| django_migrations | 54 | 迁移记录 |
| django_session | 3 | 会话 |
| sqlite_sequence | 15 | 自增序号 |

## 2. 游戏数据表建表语句（原样）

```sql
CREATE TABLE "map_map" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(64) NOT NULL, "map_file" varchar(100) NOT NULL, "places" text NOT NULL);

CREATE TABLE "monster_monster" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(64) NOT NULL, "location" varchar(64) NOT NULL, "city" varchar(64) NOT NULL,
  "bio" text NOT NULL, "agility" smallint NOT NULL, "defense" smallint NOT NULL,
  "max_attack" smallint NOT NULL, "max_health" smallint NOT NULL,
  "min_attack" smallint NOT NULL, "momentum" smallint NOT NULL);

CREATE TABLE "npc_npc" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(64) NOT NULL, "location" varchar(64) NOT NULL, "city" varchar(64) NOT NULL,
  "default_place" varchar(64) NOT NULL, "bio" text NOT NULL);

CREATE TABLE "_npc_npc_old_20230311" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(64) NOT NULL, "location" varchar(64) NOT NULL,
  "default_place" varchar(64) NOT NULL, "bio" text NOT NULL);

CREATE TABLE "stuff_stuff" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(1024) NOT NULL, "icon" varchar(100) NOT NULL, "illustrate" text NOT NULL,
  "level" smallint NOT NULL, "is_tradable" smallint NOT NULL, "weight" smallint NOT NULL);

CREATE TABLE "stuff_weapon" ("stuff_ptr_id" bigint NOT NULL PRIMARY KEY
    REFERENCES "stuff_stuff" ("id") DEFERRABLE INITIALLY DEFERRED,
  "min_attack" smallint NOT NULL, "max_attack" smallint NOT NULL, "agility" smallint NOT NULL,
  "slot" smallint NOT NULL, "durability" smallint NOT NULL, "type" smallint NOT NULL,
  "enhancement" smallint NOT NULL, "quality" smallint NOT NULL);

CREATE TABLE "stuff_armor" ("stuff_ptr_id" bigint NOT NULL PRIMARY KEY
    REFERENCES "stuff_stuff" ("id") DEFERRABLE INITIALLY DEFERRED,
  "defense" smallint NOT NULL, "agility" smallint NOT NULL, "slot" smallint NOT NULL,
  "lucky" smallint NOT NULL, "durability" smallint NOT NULL, "type" smallint NOT NULL,
  "poison_resistance" smallint NOT NULL, "enhancement" smallint NOT NULL,
  "quality" smallint NOT NULL);

CREATE TABLE "stuff_consumable" ("stuff_ptr_id" bigint NOT NULL PRIMARY KEY
    REFERENCES "stuff_stuff" ("id") DEFERRABLE INITIALLY DEFERRED);

CREATE TABLE "player_user" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "username" varchar(64) NOT NULL UNIQUE, "nick_name" varchar(64) NOT NULL,
  "avatar" varchar(100) NOT NULL, "password" varchar(64) NOT NULL,
  "phone" varchar(16) NOT NULL, "email" varchar(254) NOT NULL,
  "date_joined" datetime NOT NULL, "last_login" datetime NOT NULL);

CREATE TABLE "player_playerstatus" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "experience" smallint NOT NULL, "max_experience" smallint NOT NULL,
  "max_health" smallint NOT NULL, "min_attack" smallint NOT NULL,
  "max_attack" smallint NOT NULL, "defense" smallint NOT NULL,
  "agility" smallint NOT NULL, "momentum" smallint NOT NULL,
  "player_id" bigint NOT NULL REFERENCES "player_user" ("id") DEFERRABLE INITIALLY DEFERRED,
  "location" varchar(32) NOT NULL, "level" smallint NOT NULL, "health" smallint NOT NULL);

CREATE TABLE "player_playerstuff" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "inventory" smallint NOT NULL,
  "stuff_id" bigint NOT NULL REFERENCES "stuff_stuff" ("id") DEFERRABLE INITIALLY DEFERRED,
  "player_id" bigint NOT NULL REFERENCES "player_user" ("id") DEFERRABLE INITIALLY DEFERRED);

CREATE TABLE "player_playerequipment" ("id" integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  "stuff_id" bigint NOT NULL REFERENCES "stuff_stuff" ("id") DEFERRABLE INITIALLY DEFERRED,
  "player_id" bigint NOT NULL REFERENCES "player_user" ("id") DEFERRABLE INITIALLY DEFERRED);
```

## 3. 关键结构说明

1. **物品为多表继承**：公共属性在 `stuff_stuff`，武器/护甲/消耗品子表通过 `stuff_ptr_id` 一对一挂接（Django 多表继承）。
   判断物品类型需查三个子表；消耗品子表无字段，仅作类型标记。
2. **PlayerEquipment 无槽位字段**：玩家×物品多对多，装备穿戴位置未建模（推断按 type/slot 推断或未设计）。
3. **PlayerStuff.inventory** = 数量（可堆叠）。
4. **player_user.password 明文 varchar(64)**（非 Django hash，DB 实例存 "test"/"test2" 原文）。
5. **location varchar(32)** 存 `"['威尼斯', '酒馆']"` 字符串 —— 32 长度对长地点名偏紧，属设计缺陷。
6. **无货币/金币字段**：全库无任何经济数值字段，商店/银行/赌场无数据支撑。
7. **无任务表**：确认任务系统未建模。
8. `django_content_type` 注册的 18 个模型里有 `player.player`（已删除的旧模型）——早期还有一个 Player 模型，后被 User+PlayerStatus 取代。
9. `map_map` 自增序号=5（id=5 现存）：曾建过 4 张地图后删除；`auth_user` 序号=3：yorkzz 账号已删。
10. admin_log（49 条）完整记录了数据录入过程：地图经 5 次上传调试（2023-03-11），NPC 经 import_export 批量导入，
    物品 20 件逐条后台录入（2023-03-11/17）——即 **excel/地图.xlsx 与 物品清单就是开发者的原始策划数据**。
