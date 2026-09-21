何时读本文件：实现或改动本项目（2D 纯 UI 文字挂机游戏，Android 竖屏）的「加密存档 / 背包道具 / 货币经济 / 任务·签到·成就」时；按本项目画像裁剪，含 NEVER 陷阱与最短可用模式。

# 1. 加密存档

## NEVER Do（save/load，原文照抄）
- **NEVER save without a version field** — When you update your game's data structure, old saves will break. Always include a `"version": "1.0.0"` field and implement migration logic.
- **NEVER use absolute OS paths** — Hardcoding `C:/Users/...` will break on every other machine. Always use the `user://` protocol, which Godot maps to the correct OS-specific app data folder.
- **NEVER attempt to save Node references directly** — Nodes are objects, not raw data. Extract the necessary primitive data (positions, health, levels) into a `Dictionary` or `Resource` instead.
- **NEVER forget to close FileAccess handles** — Leaving a file open can lead to handle leaks and save-file corruption. In Godot 4, files auto-close when the variable goes out of scope, but explicit `close()` is safer for long-running logic.
- **NEVER use JSON for very large binary data** — Storing 10MB of texture data as Base64 in JSON is slow and bloats file size. Use binary `store_var()` or separate dedicated asset files.
- **NEVER trust loaded data without validation** — Users can edit save files. Always use `data.get("field", default_value)` and validate that numbers are within expected ranges to prevent crashes.
- **NEVER trigger a save during high-frequency physics or animation updates** — A crash mid-write will corrupt the file. Save only on explicit game events like entering a menu, finishing a level, or at a checkpoint.
- **NEVER modify a save Dictionary while iterating over its keys** — Calling `erase()` or `add()` inside a loop over the same dictionary causes iteration errors. Use `data.duplicate()` to iterate safely.
- **NEVER store raw passwords or sensitive credentials in unencrypted JSON** — If you have sensitive data, use `FileAccess.open_encrypted_with_pass()` to secure it.
- **NEVER rely on get_instance_id() for cross-session identification** — These IDs are assigned at runtime and change every time the game restarts. Generate your own persistent `String` UUIDs for game objects.
- **NEVER forget to call duplicate(true) on a loaded Resource stats block** — If multiple enemies load the same "goblin_stats.tres", they will all share the same health pool unless duplicated.
- **NEVER use the "allow_objects" flag in store_var/get_var for untrusted data** — Setting this to `true` allows full object decoding, which is a major security risk for saves downloaded from the web.
- **NEVER use JSON for data requiring strict type preservation** — JSON converts `Vector3` to a string or dictionary. For strict data types, use `var_to_bytes()` or a binary format.
- **NEVER leave internal metadata (set_meta) in persistent dictionaries** — This unnecessarily inflates save file size. Clean your dictionaries before serialization.

## `allow_objects` Trust Boundary（原文照抄）
Default **always** `store_var(data, false)` / `get_var(false)`.

| Case | `allow_objects` | Rule |
|------|-----------------|------|
| Player `user://` saves, workshop mods, downloads | `false` | NEVER true — RCE risk |
| Trusted local only (your own tooling, offline debug fixtures you control) | `true` only if unavoidable | Document why; never ship as default; prefer Resources / Dictionaries of primitives |

> **CAUTION:** Baseline tutorials used `store_var(data, true)`. Untrusted `user://` saves must **`allow_objects=false`** — RCE risk on modded/workshop files. Encrypted elite paths still use `false` unless the payload is explicitly trusted-local and non-user-editable.

## Golden Path (version → migrate → backup → atomic write)
1. **Version field** on every save blob.
2. **Migrate** when versions differ.
3. **Backup** existing file (`DirAccess.copy_absolute` to `.bak`) before overwrite.
4. **Write** to temp then rename, or write-after-backup; validate open errors.
5. **Integrity** optional: `FileAccess.get_sha256` compare; fall back to backup on mismatch.
6. **Paths** only `user://` — never absolute OS paths.
7. **When to save** — menu, checkpoint, level complete — never per physics frame.

## 加密方式与陷阱
```gdscript
func save_game(data: Dictionary) -> void:
    data["_version"] = CURRENT_VERSION
    var file = FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.WRITE, ENCRYPTION_KEY)
    if file:
        file.store_var(data, false)  # allow_objects=false
        file.close()
```
- 备选手动管线（AESContext）：`JSON.stringify` → `to_utf8_buffer()` → `compress(FileAccess.COMPRESSION_DEFLATE)` → `AESContext.MODE_ECB_ENCRYPT` + `ctx.update()` → `store_buffer`；读回逆序，`decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)`。
- EXPERT NOTES（原文）：`ENCRYPTION_KEY should be generated per project, store securely`；`This prevents casual save editing, NOT determined attackers`；`For multiplayer/leaderboards, validate server-side`。
- 完整性校验：`DirAccess.copy_absolute(primary, backup) == OK` 备份；`FileAccess.get_sha256(path) == expected_hash` 校验，不一致回退 `.bak`。
- 迁移：读出后 `var save_version = data.get("_version", 1)`，`if save_version < CURRENT_VERSION: data = _migrate_data(...)`，按版本链逐级补字段/改默认值，迁移完成再套用玩家状态。
- PERSIST 组模式：Nodes in group `persist` / `Persist` implement `save()` / `load()`. Manager walks `get_nodes_in_group`.
- 向量/资源路径：store `{x, y}` / `{x, y, z}` components（JSON 不保真 Vector）；资源引用存 `"texture_path": texture.resource_path`，加载时 `load(path)`。
- 存什么/不存什么：只存 ids + amounts（不嵌套 Resource 图）；设置用 `ConfigFile`（`user://settings.cfg`）与进度存档分离；自动存档只走显式事件或 Timer（如 300s），绝不每帧。

# 2. 背包与道具

## NEVER Do in Inventory Systems（原文照抄）
- **NEVER use Nodes for items** — `Item extends Resource`.
- **NEVER add without stack/weight pre-checks** — validate capacity first.
- **NEVER let UI mutate inventory arrays silently** — data owns mutations; UI listens.
- **NEVER use `float` for quantities** — `int` stacks.
- **NEVER emit per-item signals in a batch** — one `inventory_updated` after the loop.
- **NEVER hardcode item references** — String/StringName ids + database.
- **NEVER `queue_free` + recreate all slots every refresh** — reuse slot widgets.
- **NEVER allocate new Resources inside `_process`**.
- **NEVER mutate a shared item blueprint at runtime** — use `duplicate(true)` on stack/slot instances so one pickup cannot corrupt every copy of that `.tres`.
- **NEVER access `.icon` on a null slot item** — guard with `is_instance_valid()` before drawing UI.

## Resource 化道具（最短可用）
```gdscript
class_name Item
extends Resource
@export var id: String
@export var display_name: String
@export var max_stack: int = 1
@export_multiline var description: String
```

## 增删改查规则
- Add 决策树（原文）：1. Weight/volume OK? → 2. Pass 1: fill partial stacks → 3. Pass 2: empty slots / grid footprint → 4. Return overflow count; single UI signal。
- 加满判断用 `mini()`：先补 `max_stack - slot.amount` 的半满堆，再开新格；`find_empty_slot() == null` 即背包满，返回 false/溢出数。
- remove 先统计持有量（同 `has_item`：累加所有匹配 slot 的 amount），不足直接 return false 不动手；减到 0 的 slot 调 `clear()`。
- UI：Bind once to `inventory_updated`；Update existing slot nodes; create only when slot count grows。运行时实例 `duplicate(true)` 后再改数量。

## 存档（背包切片）
- Serialize `item_id` / `resource_path` + `amount` only。载入时按 id 从 ItemDatabase 取蓝图再灌数量；`inventory_changed.emit()` 收尾。

# 3. 经济与资源循环

## 货币表示决策表（原文照抄）
| Economy type | Store as | Why |
|--------------|----------|-----|
| Soft currency (gold, scrap) with UI decimals | **`int` cents / smallest unit** | Exact math; display `value / 100.0` |
| Premium / idle quantities >> 2^31 | **BigInt / multi-limb int** (or carefully scaled `float` only if approx OK) | 32-bit `int` caps ~2.1B |
| Multiplayer / persistent wallet | **Authoritative `int` (or BigInt) on server** | Client never finalizes spends |
| Prices with fractional display only | Still **int smallest unit** | Avoid `0.1 + 0.2` float drift |

**NEVER** mix "use float for money" and "never use float for money" without this tree — pick one column and stick to it.

## NEVER Do in Economy Systems（原文照抄）
- **NEVER skip buy/sell spread** — Same buy/sell price = infinite money.
- **NEVER skip currency sinks** — Repairs, taxes, fees, consumables prevent inflation.
- **NEVER validate spends only on the client** — Server/host is source of truth in multiplayer.（单机也要：校验集中在 Wallet/Transaction 单例，UI 不可直接改）
- **NEVER hardcode loot weights in scripts** — Use Resources.
- **NEVER subtract before `current >= amount`** — Underflow / negative wallets corrupt saves.
- **NEVER let UI mutate balances directly** — UI requests; wallet/transaction manager decides.
- **NEVER ignore transaction logs in serious RPGs** — Audit trail for missing currency.
- **NEVER exceed max caps without clamping** — Cap before wrap / overflow.

## Wallet / 事务管线（最短可用）
```gdscript
signal balance_changed(currency_id: String, new_amount: int)
var balances: Dictionary = {}  # currency_id -> int
func spend_funds(currency_id: String, amount: int) -> bool:
    var current: int = balances.get(currency_id, 0)
    if current >= amount:
        balances[currency_id] = current - amount
        balance_changed.emit(currency_id, balances[currency_id])
        return true
    return false
```
- 原子购买顺序（原文要点）：1. cost < 0 拒绝 → 2. 余额检查 → 3. 背包容量检查（Atomic Step 1）→ 4. 扣款+入包（Atomic Step 2）→ 5. emit transaction 信号。
- 买卖价差：> **CAUTION:** `sell_price == buy_price` enables infinite arbitrage. Typical sell = 50% of buy unless design says otherwise.（`int(buy_price * markup)`）
- 掉落/稀有度表用 Resource（weights / rarity），随机用 Godot RNG API，不写在脚本里的硬编码 `%`。

## 与挂机产出的衔接点
- 挂机/离线收益、任务奖励一律走 transaction API 发放（quest gold rewards and turn-in sinks wire rewards through the transaction API, not ad-hoc `gold +=`）。
- Loot → wallet bridge：产出事件监听后调 `add_funds`，经济规则不内嵌进产出节点。
- 钱包字典随进度存档（currency_id → amount，带 version + 校验）；never leave soft currency only in memory。
- 通胀遥测（可选）：`[ECON]:amount` 日志行算 gold-per-minute；**NEVER** `print()` inside `Logger._log_message` — recursion crash。

# 4. 任务 / 每日签到 / 成就

## NEVER Do in Quest Systems（原文照抄）
- **NEVER store active quests only on the Player node** — Autoload / persistent data.
- **NEVER use unverified plain string ids** — `StringName` / registry (`&"kill_slimes"`).
- **NEVER forget to disconnect completion signals** — double rewards.
- **NEVER poll objectives in `_process`** — signal-driven.
- **NEVER skip save/load for quest state**.
- **NEVER hardcode quest logic inside enemy/item scripts** — triggers/bus.
- **NEVER award loot inside the Quest Resource** — emit; inventory/economy grant.
- **NEVER allow duplicate active instances of the same quest id**.

## Golden path（原文照抄）
```
accept → event trigger → progress → complete → persist
```
| Checkpoint | Action |
|---|---|
| **Accept** | `QuestManager.accept_quest(quest)` — duplicate Resource if runtime mutation; connect `quest_completed` once |
| **Event trigger** | Kill/collect/talk via trigger nodes / bus — **not** hardcoded in enemy scripts |
| **Progress** | `update_objective(quest_id: StringName, …)` — interned ids only |
| **Complete** | Manager erases active, emits `quest_completed`, grants via inventory/economy signals |
| **Disconnect** | Disconnect completion Callables when quest leaves active set — prevent double rewards |
| **Persist** | Save active/completed id maps + counts — not live Resource graphs |

## Resource 化定义（最短可用）
```gdscript
class_name Quest extends Resource
@export var quest_id: StringName
@export var objectives: Array[QuestObjective] = []
func is_complete() -> bool:
    return objectives.all(func(obj): return obj != null and obj.is_complete())
```
> **CAUTION:** `objectives.all(...)` on arrays with null entries crashes — null-check in `is_complete()`.
- Objective：`objective_id: StringName` + `required_amount: int`，`current_amount = mini(current_amount + amount, required_amount)`。
- Field alignment（原文）：`quest.id: StringName`、`objective_id: StringName`、Manager dictionaries keyed by `StringName`；hooks compare `StringName`, not free strings。
- 管理器为 Autoload 单例，active/completed 集合不在 Player 节点上。

## 存档与每日重置
- 存 active/completed 的 `id → 进度计数` 映射（JSON 字典）；载入时从 QuestDatabase 取基础 Resource 再 accept + update_objective 回填，**NEVER** serialize live Quest Resource graphs with mutable `current_amount` on shared `.tres` files。
- 成就 = 一次性 quest：completed id 集合持久化，绝不重置。
- 每日任务/签到 = quest + 每日重置：存档记上次重置的日期（如 `Time.get_date_string_from_system()`），加载或跨零点比较后把对应 id 的计数清零重新可领；领取记录（防重复领）一并入库。
- 时间相关规则（原文）：time-limited 用 `SceneTree.create_timer(time_limit).timeout` 驱动失败路径（`status = Status.FAILED`），不 `_process` 轮询；UI tracker 只从 manager 信号重建，UI must not compute progress formulas。

<!-- 来源映射
- 加密存档: godot-save-load-systems（SKILL.md + references/save-patterns-deep.md + scripts/save_system_encryption.gd、save_integrity_validator.gd、save_migration_manager.gd）
- 背包与道具: godot-inventory-system（SKILL.md + references/core-architecture.md、inventory-manager.md、save-load.md、ui-integration.md + scripts/inventory_persistence.gd）
- 经济与资源循环: godot-economy-system（SKILL.md + references/economy-elite-patterns.md + scripts/wallet_manager_singleton.gd、transaction_manager.gd、economy_persistence_handler.gd）
- 任务/每日签到/成就: godot-quest-system（SKILL.md + references/quest-patterns-deep.md + scripts/quest_persistence_loader.gd、timed_quest_challenge.gd）
-->
