何时读：设计或修改挂机产出循环、成长/成本曲线、大数字与展示格式、离线结算时读本文件。

## 1. 挂机生产循环（tick 设计与产出计算）

NEVER（原文保留）：
- NEVER use `Timer` nodes for revenue generation; strictly use a manual accumulator in `_process(delta)` to prevent drift during frame fluctuations.
- NEVER update all UI labels every frame; strictly use **Signals** to update labels ONLY when values change, or throttle updates to 10 FPS.
- NEVER ignore **Low Processor Usage Mode** for mobile; strictly enable `OS.low_processor_usage_mode = true` to preserve battery life.
- NEVER update massive logs by modifying the `text` property; strictly use `append_text()` to prevent main thread blocking.
- NEVER instantiate/delete hundreds of text nodes per second; strictly use **Object Pooling** for click-feedback.

最短可用循环：
```gdscript
var accumulator := 0.0
func _process(delta: float) -> void:
    accumulator += delta
    if accumulator >= 0.1: # 10 FPS 结算节流，移动端省电
        currency += income_per_second() * accumulator
        accumulator = 0.0
        currency_updated.emit() # UI 只在值变化时刷新
```
- 产出公式：产出 = 每秒总收益 × 实际经过秒数；每秒总收益 = 全部生产者 revenue 一次性求和，每帧只算一次。
- 文字游戏的点击反馈同样遵守池化原则，不要每次点击 new/queue_free 节点。

## 2. 数值成长曲线（成本/收益公式与系数）

- NEVER hardcode generator costs or growth; strictly use an exponential formula: `Cost = BasePrice * pow(GrowthFactor, OwnedCount)` (industry standard **1.15x**).
- NEVER evaluate exact float equality (`==`); strictly use `is_equal_approx()` or `>=` to prevent "stuck" progress due to precision loss.

最短可用生成器（Resource 驱动，平衡在 Inspector 调）：
```gdscript
class_name Generator extends Resource
@export var id: String
@export var base_cost: float
@export var base_revenue: float
@export var cost_growth_factor: float = 1.15
var count: int = 0
func get_cost() -> float:
    return base_cost * pow(cost_growth_factor, count)
```
- 每个生产者/养成项一个 `.tres`；改数值不改代码。
- Prestige（重置换永久成长）参考公式：`global_multiplier = 1.0 + prestige_currency * 0.10`；NEVER make the "Prestige" reset feel like a loss; strictly provide a global multiplier that makes the next run **significantly** faster (2-5x).
- 平衡验收：用"分钟级里程碑带"（minutes-to-milestone）验证曲线节奏，不凭单点手感调系数。

## 3. 大数处理（数值溢出边界与展示格式化）

- NEVER use standard floats for currency; strictly implement a **BigNumber** (Mantissa/Exponent) system (e.g., `1.5e300`) to prevent `INF` crashes at 1e308.
- NEVER parse scientific notation strings with `to_int()`; strictly use `to_float()` or a dedicated BigNumber parser.
- 边界事实：64 位 float 在 ~1.8e308 变 `INF`。数值曲线封顶在 1e15 内可先用 int64；货币字段存档一律存字符串（如 `"1.5e300"`），留好切换 BigNumber 的余地。

最短可用 Mantissa/Exponent（超出 float 范围再启用）：
```gdscript
class_name BigNumber extends RefCounted
var mantissa: float = 0.0 # 归一化到 1.0..10.0
var exponent: int = 0
func _init(m := 0.0, e := 0) -> void:
    mantissa = m; exponent = e; normalize()
func normalize() -> void:
    while abs(mantissa) >= 10.0: mantissa /= 10.0; exponent += 1
    while abs(mantissa) < 1.0 and mantissa != 0.0: mantissa *= 10.0; exponent -= 1
func multiply(o: BigNumber) -> BigNumber:
    return BigNumber.new(mantissa * o.mantissa, exponent + o.exponent)
```

展示格式化（K/M/B 后缀，超出后缀表转科学计数法）：
```gdscript
static func format(bn: BigNumber) -> String:
    if bn.exponent < 3:
        return str(int(bn.mantissa * pow(10, bn.exponent)))
    var suffixes := ["", "K", "M", "B", "T", "Qa", "Qi"]
    var idx := bn.exponent / 3
    if idx < suffixes.size():
        return "%.2f%s" % [bn.mantissa * pow(10, bn.exponent % 3), suffixes[idx]]
    return "%.2fe%d" % [bn.mantissa, bn.exponent]
```
- 读档：科学计数字符串按 "e" 拆 mantissa/exponent 用专用解析，禁止 `to_int()`。

## 4. 离线收益（时间戳计算、与加密存档的衔接点）

- NEVER ignore **Offline Progress**; strictly calculate `seconds_offline * total_revenue` using system UNIX timestamps (`Time.get_unix_time_from_system()`).
- NEVER calculate offline time using `Time.get_ticks_msec()`; strictly use **Persistent UNIX timestamps** as ticks reset on app restart.

与加密存档的衔接点：
- 存档 payload 内写 `timestamp = Time.get_unix_time_from_system()`，随整个 payload 一起加密落盘 `user://`；读档解密后取回。
- 启动结算：`seconds_offline = now - save_data.timestamp`；设下限（>60 秒才结算）与上限（如封顶 8 小时）防无限囤积破坏曲线。
- 金额 = 每秒总收益 × seconds_offline；入账必须走统一入口，结算后弹欢迎回归提示。
- 时间源处注释"联机后改用服务器时间"（见 multiplayer-readiness.md 原则 7）。

<!-- 来源映射
- 挂机生产循环: godot-genre-idle-clicker（SKILL.md NEVER 清单 + references/expert-idle-clicker-patterns.md 架构总览）
- 数值成长曲线: godot-genre-idle-clicker（SKILL.md NEVER 清单 + references/expert-idle-clicker-patterns.md generator.gd 与 prestige 公式）
- 大数处理: godot-genre-idle-clicker（references/expert-idle-clicker-patterns.md big_number.gd 与 Formatting Numbers）
- 离线收益: godot-genre-idle-clicker（SKILL.md NEVER 清单 + references/expert-idle-clicker-patterns.md OfflineProgressionManager）
-->
