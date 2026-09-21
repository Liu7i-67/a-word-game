# A Word Game · 纵横四海

基于 Godot 4.7.1 的文字冒险游戏，复刻《纵横四海》网页文字 MUD 的核心机制（设计文档：`D:\Documents\纵横四海\游戏设计机制.md`）。2D 纯 UI 驱动，竖屏触屏操作，目标平台 Android。

## 当前实现（最小可玩版）

- **开场 7 页剧情（逐字原文）+ 角色创建**（名字 + 注册男/注册女）
- **威尼斯城内 25 场景**：方向出口移动（含未开放区域占位）、城内地图直达、码头地中海传送列表
- **NPC 对白**：酒馆老板指引 / 四城门守卫 / 探险官（地宫）/ 国王 / 银行职员 / 博彩MM / 供应商 / 神父 / 福利官，文案取自逆向文档；其余 NPC 为占位
- **战斗闭环**：农场病鸡（攻防区间随机 + 防御减伤 + 经验/铜贝/装备掉落 + 撤退付费 + 战败丢钱回城 + 武器耐久损耗）
- **经济闭环**：福利（每周 10000 铜贝）→ 市场（葡萄酒/橄榄油 900/450/225 箱买卖，卖价 50%）→ 赌场（猜拳/赌大小，200 下注 1 赔 5）→ 银行（铜贝↔银贝存取，消费自动从银行折兑）
- **装备系统**：状态/物品页、装备详情、使用手持/卸下、等级与负重校验
- **本地加密存档**：场景切换/战斗结束/交易等事件自动存档，Android 暂停与桌面关闭时兜底存档

数值公式为文档缺失部分的🔍合理补全，**全部集中在 `data/config.json`**（来源标注见其 `_doc`）。

## 开发

用 Godot 4.7.1 打开本目录（本机：`E:\qbb\Godot_v4.7.1-stable_win64.exe\`）。

```
# 全量自测（数据校验/数值/战斗/事件链路/存档往返）
Godot --headless --path . -s scripts/self_test.gd

# 页面截图走查（输出 SHOT_DIR，默认 user://shots）
SHOT_DIR=E:/qbb/github/a-word-game/.shots Godot --path . --audio-driver Dummy -- --shot-tour
```

## 打包安卓 APK

```
build.bat                    # patch 版本号 +1 并打包
build.bat -VersionBump none  # 不改版本号，仅重新打包
```

依赖：Android SDK（本机 `E:\qbb\soft\android_sdk`）、导出模板、签名 keystore（`env/upload-keystore.jks`，沿用 a-game 的上传密钥）。产物输出到 `builds/`。`data/*.json` 经 `export_presets.cfg` 的 include_filter 打入包体。

## 目录结构（feature-based）

- `scenes/main/` — 主场景（唯一 tscn，界面全部代码构建）
- `scripts/autoload/` — EventBus（past-tense 总线）、SaveManager（加密存档唯一入口）、PlayerState（玩家状态持有，`class_name PlayerCore`）、GameManager（流程编排）
- `scripts/data/game_data.gd` — `data/*.json` 静态加载与查询
- `scripts/game/` — Rules（数值公式）、CombatEngine（战斗）、Pages（BBCode 页面构建）、EventRouter（event 事件分发，对应原版超链接分发）
- `scripts/ui/` — PageView（RichTextLabel 超文本视图）、TitleScreen、GameScreen
- `scripts/dev/shot_tour.gd` — 开发用截图走查
- `data/` — config / story / items / monsters / scenes 五张 JSON 表（逻辑与数据分离）
- `assets/`、`env/` — 美术字体资源 / 签名 keystore（勿外传）
- `.agents/skills/godot-word-game/` — 项目 Godot 开发规则（做 Godot 任务先读）

## 后续待办

- 更多怪物/装备/商品表、城外区域（矿山/海滩等 14 个占位出口）、其他港口城市
- 威尼斯地宫（5-15 级团队任务）、铁匠打造、商店药品（战斗中吃 Apple/药剂）
- 设置菜单（settings.cfg 与进度存档分离）、BGM/音效、CJK 字体内置（当前依赖系统字体回退）
- 包名 `com.example.awordgame` 上架前需修改
