# 00 - 仓库总览（zhsh-ref：《纵横四海》Django 重实现骨架）

> 提取日期：2026-09-21。源仓库：`E:\qbb\github\zhsh-ref`（浅克隆，仅 1 个 commit：`938f0e8 待完善首页`）。
> 本文只做提取与分析，未修改源仓库任何文件。

## 1. 这个仓库到底是什么

这是《纵横四海》（老文字 MUD/MUD 类网页游戏）的一次 **Django 4.1.7 重实现的早期骨架**，只做了：

- 后台（Django admin）+ 数据导入（django-import-export）
- 5 个数据 App：`map`（地图）、`monster`（怪物）、`npc`、`stuff`（物品）、`player`（玩家）
- 1 个几乎为空的前台页面（`templates/location.html`，仅显示玩家当前所在地）

**没有实现任何玩法逻辑**：无战斗、无商店/经济、无任务、无对话、无赌场/银行代码。
仓库价值 = **原始游戏数据 + 数据模型（字段即机制蓝图）+ 后台配置**。

requirements.txt：`django==4.1.7, pandas==1.5.3, mysqlclient, openpyxl==3.1.1, django-import-export==3.0.2, pillow==9.4.0`
（settings.py 实际配置的是 sqlite3，见 `zhsh/settings.py:63-68`；mysqlclient 是预留生产库）

## 2. 目录与文件清点

| 路径 | 内容 |
|---|---|
| `db.sqlite3` (260KB) | 唯一数据库，含全部已录入数据（见 06-db-schema.md） |
| `excel/地图.xlsx` | **51×51 大世界地图草稿**，sheet 名「威尼斯」，含野外区域（废弃堡垒/废墟/矿洞/矿山/农场）+ 威尼斯城 + 实验室，共 30 个唯一地名。**未导入 DB，是最新最全的地图** |
| `excel/怪物.xlsx` | 怪物导入**空模板**（Tablib 格式，仅表头：id,name,max_health,min_attack,max_attack,defense,agility,momentum,location,city,bio），0 行数据 |
| `file/maps/地图.xlsx` | 26×26 威尼斯城地图（5×5 城区，22 地点），源文件 |
| `file/maps/地图_SDLxQ4n.xlsx` | 上者的 Django 上传副本（内容相同，仅行列索引标签 0-24 vs 1-25），即 DB 中 map id=5 绑定的文件 |
| `file/media/stuff/icon/…` | 20 件物品的图标（64×64 png/bmp，文件名为**原版游戏图标资源 id**，如 1107=乾坤袋、915=龙泉水） |
| `file/media/user/avatar/…` | 测试玩家头像（复用物品图标） |
| `file/1107.png` | 乾坤袋图标原图 |
| `map/ monster/ npc/ stuff/ player/` | Django App：各含 models.py（数据模型=机制蓝图）、admin.py（后台配置）、空 views.py/tests.py |
| `templates/` | base.html（Bootstrap5 骨架）、header.html（空壳）、location.html（首页，只显示 `location.location.0 + .1` 即 城市+地点） |
| `zhsh/` | Django 工程配置（settings/urls，路由仅 `/admin/`、`/file/`、`/static/`、`/`=首页） |
| `static/` | settings 中引用但**目录不存在** |

git 历史仅 1 commit，`.gitignore` 忽略 `/*/migrations/`（迁移文件未入库）。

## 3. 数据分布与数量总表

| 域 | DB 已录入 | excel/文件补充 | 完整度 |
|---|---|---|---|
| 地图 | 1 张（威尼斯，map id=5，25×25 网格 JSON，22 个城区地点） | 51×51 大世界（30 个唯一地名，含 6 个野外区域+实验室） | 地图框架齐全，多城市缺失 |
| 怪物 | **0 只**（表存在、导入模板存在，但无数据） | 模板表头 | **完全缺失** |
| 物品 | 20 件（武器2 / 护甲2 / 消耗品15 / 未分类1） | 图标 20 个 | 类型体系完整，数量少，无价格字段 |
| NPC | 7 个（全部在威尼斯·酒馆） | — | 有简介无对话 |
| 任务 | **0**（无模型、无数据） | — | **完全缺失** |
| 玩家 | 2 个测试号（test/test2），各 1 份 PlayerStatus（Lv1 初始值） | — | 仅初始状态样例 |
| 玩法代码 | 无战斗/经济/任务代码 | — | 只能从字段与文案反推 |

DB 里的痕迹（sqlite_sequence / admin_log）表明曾录过 5 张地图、3 个用户（yorkzz/test/test2），后删除了部分；
`_npc_npc_old_20230311` 是 2023-03-11 的 NPC 旧表备份（空表，字段缺 city）。

## 4. 机制清单总览（详见 05-mechanics.md）

1. **地图=excel 网格**：上传 xlsx → pandas 读取 → 每格一个地点名 → JSON 存 `places` 字段（map/models.py:18-30）
2. **坐标制移动**：玩家位置存 `['城市','地点']` 字符串（Python list repr），地点必须存在于城市网格
3. **怪物/NPC 落位校验**：所在地点必须在所属城市的 places 里，否则拒绝保存（monster/models.py:27-32, npc/models.py:22-29）
4. **属性七件套**：生命/最小攻击/最大攻击/防御/敏捷/士气 + 经验等级（玩家与怪物同构，暗示战斗公式对称）
5. **物品五类型六品质**：武器/护甲/药品/消耗品/任务物品；普通→传奇（stuff/models.py:8-22）
6. **装备词条**：攻击区间、防御、敏捷、耐久350、宝石插槽、强化等级、幸运一击、毒抗（武器/护甲模型）
7. **文案即玩法**：20 件物品说明里透露了体力系统、双倍经验、强化、技能书、钓鱼、农场、改名等规划系统
8. **七酒馆 NPC**：马戏团、怪博士、教官、吧女、神秘人等，bio 即任务钩子

## 5. 各文档导引

- `01-maps.md` — 威尼斯城 5×5（DB 版）+ 51×51 大世界网格（excel 版，含 ASCII 渲染与全部坐标）
- `02-monsters.md` — 怪物模型字段、导入模板、（空）数据
- `03-items-stuff.md` — 20 件物品全量逐条 + 装备词条体系
- `04-npcs-quests.md` — 7 个 NPC 全文简介 + 任务系统缺失说明
- `05-mechanics.md` — 从代码逐条提取的规则与公式（带文件:行号）
- `06-db-schema.md` — 全部 20 张表的建表语句与行数
