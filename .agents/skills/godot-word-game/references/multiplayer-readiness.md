何时读：写任何会改动玩家数据/游戏状态的代码之前读本文件；这些原则决定今天的单机代码日后能否平移到联机（本文件不含任何网络实现）。

## 单机今天就要守的架构预留原则

1. **意图与模拟分离（状态所有权）**
   - 原文：Separate **input** (client) from **simulation** (authority). / Clients own their 'Input', NOT their 'Position' or 'Health'.
   - 单机做法：触屏/UI 只发"意图"（`attempt_xxx`），永远不直接改状态；模拟层独占数据修改权。

2. **数据变更走统一入口**
   - 原文：**NEVER trust client-reported state** — Clients own their 'Input', NOT their 'Position' or 'Health'. Server must validate every coordinate and health change.
   - 单机做法：所有货币/物品/数值变更只经一个入口（如 `Economy.add_currency(amount, reason)`），入口内校验并记 `reason`；UI 层散落直改 = 联机时全部重写，也让防篡改加密存档失去意义。

3. **玩家数据与呈现分离**
   - 原文：NEVER use Node hierarchies for raw data; strictly use `RefCounted` or `Resource` objects for lightweight, serializable logic.
   - 单机做法：数据放 RefCounted/Resource（可序列化、无 Node 依赖），Label 只靠信号刷新；Label 反向改数据是红线。

4. **动作/命令模式雏形**
   - 单机做法：每个操作建模为带 `reason` 的命令（buy_item / use_item / claim_daily），统一走入口校验+执行；联机后这些命令天然可回放、可由权威端复验（clients send intents only）。

5. **完整快照可序列化**
   - 原文：**NEVER ignore 'Late Joiners'** — Players who join mid-game won't see existing environmental changes. Broadcast a full world-state 'Snapshot' on peer connection.
   - 单机做法：把存档当成"新会话的 late-join snapshot"——任意时刻能从存档完整重建全部状态；禁止状态散落在节点属性里而没有统一序列化出口。

6. **游戏逻辑不碰传输，边界 IO 收口到一个桥**
   - 原文（rpc_bridge 模式）：gameplay emits local signals; bridge validates authority and fans out RPCs.
   - 单机做法：游戏逻辑只 emit 本地信号；存档、（未来的）网络等"跨边界 IO"集中在一个 autoload 桥层，逻辑层不出现任何传输概念。

7. **时间源显式标注**
   - 原文：NEVER calculate offline time using `Time.get_ticks_msec()`; strictly use **Persistent UNIX timestamps** as ticks reset on app restart.
   - 单机做法：离线收益/每日重置/签到用 `Time.get_unix_time_from_system()`，并在调用处注释"联机后改用服务器时间"；`ticks_msec` 仅限帧间隔/性能测量。

8. **权威所有权写进数据结构**
   - 单机做法：字段注释归属——"玩家的"（货币、背包）走玩家意图修改，"系统/世界的"（每日任务刷新、签到日期、成就判定）将来归权威端；今天只是注释，联机时就是同步边界。

意图入口最短示例：
```gdscript
signal currency_changed
var currency := 0.0
func attempt_spend(cost: float, reason: String) -> bool:
    if currency < cost:
        return false          # 校验只在统一入口内
    currency -= cost          # 模拟层独占修改权
    currency_changed.emit()   # UI 只听信号，不回写
    return true
```

<!-- 来源映射
- 原则 1/2/4/8: godot-adapt-single-to-multiplayer（SKILL.md：NEVER trust client-reported state、Migration golden path 步骤 1-2、clients send intents only）
- 原则 3: godot-adapt-single-to-multiplayer（Migration golden path 输入/模拟分离）+ godot-genre-idle-clicker（SKILL.md NEVER：Node 层级不存原始数据）
- 原则 5: godot-adapt-single-to-multiplayer（SKILL.md：NEVER ignore Late Joiners / world-state Snapshot）
- 原则 6: godot-adapt-single-to-multiplayer（SKILL.md：rpc_bridge 模式 gameplay emits local signals）
- 原则 7: godot-genre-idle-clicker（SKILL.md NEVER：Time.get_ticks_msec / Persistent UNIX timestamps）
-->
