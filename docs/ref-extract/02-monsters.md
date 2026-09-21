# 02 - 怪物提取

## 1. 结论：原仓库怪物数据为 0

- `monster_monster` 表 **0 行**（db.sqlite3）。
- `sqlite_sequence` 显示该表自增序号为 0，即**从未录入过任何怪物**。
- `excel/怪物.xlsx` 仅为导入模板（Tablib Dataset 格式），仅 1 行表头，0 行数据。

## 2. 导入模板表头（excel/怪物.xlsx，即官方规划的怪物字段）

```
id, name, max_health, min_attack, max_attack, defense, agility, momentum, location, city, bio
```

## 3. 模型定义（monster/models.py，机制蓝图）

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| name | varchar(64) | — | 怪物名称 |
| max_health | smallint | 100 | 最大生命值 |
| min_attack | smallint | 1 | 最小攻击 |
| max_attack | smallint | 3 | 最大攻击 |
| defense | smallint | 1 | 防御值 |
| agility | smallint | 1 | 敏捷 |
| momentum | smallint | 1 | 士气 |
| location | varchar(64) | — | 所在地（城市内地点名） |
| city | varchar(64) | — | 所在城市（choices 动态取自 Map 表全部城市名，models.py:14-16） |
| bio | text(1024) | "" | 怪物简介 |

**落位校验**（monster/models.py:27-32）：保存时检查 `location` 出现在该城市 `places` JSON 文本中（子串匹配），否则抛
`ValueError("城市%s没有%s这个地点！")`。即怪物只能挂在已有地图格上。

**与玩家属性完全同构**（对比 player/models.py PlayerStatus）：max_health/min_attack/max_attack/defense/agility/momentum
一一对应 —— 战斗设计上是玩家属性 vs 怪物属性的对称对抗，士气(momentum)为双方共有的特殊属性（用途未实现，推测影响先手/暴击/逃跑）。

## 4. 后台配置（monster/admin.py）

- ImportExportModelAdmin：支持 excel 批量导入/导出（即 excel/怪物.xlsx 的用途）。
- `add_fieldsets` 与 list_display：`(name, max_health, min_attack, max_attack, defense, agility, momentum, location, city, bio)`。
- 搜索字段：name / city / bio。

## 5. 复刻建议

数值需自行设计；可直接套用本字段结构。参考原游戏同类 MUD 的惯例与仓库内物品数值量级
（玩家初始 min_atk 1 / max_atk 3 / def 1 / hp 100，武器 长剑 2-5 攻），建议 1 级怪 hp≈30-100、攻 1-5 起步。
TODO 挂载点：城内（酒馆等安全区应无怪）、矿山/矿洞/废墟/废弃堡垒为野外刷怪区（01-maps.md 区域明细）。
