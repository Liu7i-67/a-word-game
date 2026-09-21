---
name: godot-word-game
description: a-word-game 的 Godot 开发规则（文字冒险/挂机养成，2D 竖屏，Android 优先，单机起步预留联机）。项目内凡涉及 Godot / GDScript / 场景 / 存档 / 背包 / 任务 / 成就 / UI 等开发任务必须加载：含本项目架构约定与必守反模式清单。
---

# a-word-game 项目开发规则

## 项目画像

- **玩法**：文字冒险/挂机养成（文本叙事 + 数值成长 + 资源循环）
- **形态**：2D、纯 UI/Control 驱动——无物理、无 tilemap、无精灵动画、无摄像机系统
- **平台**：Android 优先（竖屏 720×1280、触屏点击），桌面仅开发调试；不做 iOS/Web/主机
- **引擎**：Godot 4.7.1，Mobile 渲染器
- **联机策略**：单机起步，架构预留联机升级兼容（现在不写任何联机实现，原则见 `references/multiplayer-readiness.md`）
- **系统**：本地加密存档（适度防篡改，严格校验留给联机服务端）、设置菜单、背包/道具、每日任务/签到、成就
- **Autoload 约定**：GameManager（编排）、SaveManager（唯一存档读写入口）、EventBus（跨场景 past-tense 事件）

## 核心规范（任何改动前必读）

### 一、目录组织与命名约定

### NEVER Do (Expert Anti-Patterns)
- **NEVER group by file type** — `/scripts`, `/sprites` folders. Nightmare maintainability. Use feature-based: `/player`, `/ui`.
- **NEVER mix snake_case and PascalCase in files** — Standard: snake_case for files, PascalCase for nodes.
- **NEVER use hardcoded get_node() paths** — Brittle on reparenting. Use `%SceneUniqueNames` for stable references.
- **NEVER modify globally shared Resources directly** — Strictly call `duplicate(true)` for unique instances with independent state.
- **NEVER forget .gitignore** — Committing `.godot/` folder = 100MB+ bloat + conflicts.
- **NEVER skip .gdignore for raw assets** — Design source files (`.psd`, `.blend`) in root will be imported unless ignored.

### Naming Conventions
- **Files & Folders**: `snake_case`. **Nodes**: `PascalCase`. **Exports**: `snake_case`; Inspector Title-Cases them.
- **Private**: leading `_` on members and virtuals (`_ready`, `_process`). **Signals**: past-tense `snake_case` (`health_changed`).
- **Unique Names**: `%SceneUniqueNames` over brittle `get_node()` paths.

### Feature-Based Organization
Group by feature (`/entities/player`, `/ui/main_menu`), not by file type. Keep `/common`, `/levels`, `/addons`.

### 二、GDScript 硬规则与 Top 陷阱

### NEVER Do in GDScript
- **NEVER use `@onready` and `@export` on the same variable** — Initialization order will cause `@onready` to overwrite the Inspector value.
- **NEVER modify a Dictionary's size while iterating it** — Use `dict.keys().duplicate()` or iterate a clone to safely erase elements.
- **NEVER use string-based `connect("signal", ...)`** — Always use the Signal object syntax (`button.pressed.connect(...)`) for compile-time safety.
- **NEVER attempt to override non-virtual native engine methods** — Overriding `queue_free()` or `get_class()` is unsupported and will be ignored by engine callbacks.
- **NEVER use dynamic `get_node()` or `$` inside `_process()`** — Fetching paths every frame stalls the CPU. Cache and use `@onready`.
- **NEVER use `Parent.method()` calls** — Violates "Signal Up, Call Down". Use signals to communicate with parents.
- **NEVER use `is` followed by a hard cast** — If the type check passes but the object changes, it crashes. Use `as` and check for null.
- **NEVER use `print()` for production debugging** — Use `push_error()`, `push_warning()`, or breakpoints.
- **NEVER pre-load huge resources in `_ready()`** — Use `ResourceLoader.load_threaded_request()` for async loading.
- **NEVER use global variables in Autoloads when `static var` is sufficient** — Static variables offer better encapsulation.

### Quick Landmines
- Prefer `dict.get("key", default)` over `dict["key"]` when presence is uncertain.
- Toggle **Access as Scene Unique Name** and read via `%Name` for critical UI/nodes.
- Script layout order: `extends` → `class_name` → signals/enums/consts → exports/onready → lifecycle → public → `_private`.

### Typed GDScript（新代码基线）
- `:=` when RHS type is obvious; always explicit `-> void` return types.
- Typed collections unlock optimized opcodes: `Array[Enemy]`, `Dictionary[StringName, float]`; prefer typed math helpers `absf` / `ceili` / `clampf`.
- `as Timer` for safe casts.
- Project Settings → Debug → GDScript → Untyped Declaration = `Warn` or `Error`.

### Callable & await
- Extra context on callback? `Callable.bind(...)`; discard unused signal args? `Callable.unbind(n)`.
- Sequence timers without threads? `await` chains (`await get_tree().create_timer(1.0).timeout`).
- Global state without Autoload bloat? `static var` (+ nullify large statics when done).

### 三、信号架构

### Signal Up / Call Down
- **Children → parents:** past-tense signals (`health_changed`, `died`).
- **Parents → children:** direct calls / properties (`apply_damage`, `play_anim`).
- **Siblings:** parent mediator or carefully scoped Autoload bus — never sibling hard refs.
- **Use signals for:** UI presses, death → game over, loot → inventory, cross-scene bus events.
- **Use direct calls for:** parent commanding child, local property access.
- Emit-on-setter: `var health: int = 100:` with `set(value): health = clamp(value, 0, max_health); health_changed.emit(health, max_health)`.

### NEVER Do in Signal Architecture
- **NEVER use signals to dictate behavior top-down** — Signals are past-tense events (e.g., "died"). Use direct method calls for commands (e.g., "kill").
- **NEVER connect a signal twice to the same Callable** — This throws an `ERR_INVALID_PARAMETER` at runtime unless using the `Object.CONNECT_REFERENCE_COUNTED` flag to stack connections.
- **NEVER use a Global Signal Bus for local data** — Pollutes global state and makes debugging harder. Use local connections for scene-specific logic.
- **NEVER assume callbacks must accept all signal arguments** — Use `unbind()` to drop unwanted parameters and keep your API clean.
- **NEVER create circular signal dependencies** — A signals B, B signals back to A? Use a mediator (parent or AutoLoad) to break the loop.
- **NEVER skip signal typing** — `signal moved` without types lacks editor support. Always use `signal moved(dir: Vector2)`.
- **NEVER forget to disconnect dynamic signals** — Ghost connections cause "call on null instance" errors. Disconnect in `_exit_tree()` or when retargeting.
- **NEVER emit signals with immediate side effects on the emitter** — If `died.emit()` calls `queue_free()`, listeners might fail to respond. Emit first.
- **NEVER use signals for high-frequency data streams** — Sending 1000+ signals/second (like per-particle updates) is inefficient. Use shared arrays or direct buffers.
- Lambdas that capture locals are NOT auto-disconnected when their node frees — disconnect manually in `_exit_tree()`.
- `CONNECT_REFERENCE_COUNTED` means multiple identical connects share one refcounted connection — it does **not** auto-clean capturing lambdas.

### 所有权决策树（先问三问：属于单个 feature？是跨场景的生命周期服务吗？发布/订阅者众多且无归属吗？）

| Need | Prefer | Avoid |
|------|--------|-------|
| Everything for one feature (player, HUD panel) | **Feature folder** scene module | Type folders (`/scripts`, `/sprites`) |
| Cross-scene service with lifecycle (save, audio bus) | **Autoload** | Stuffing UI nodes into singletons |
| Many publishers/subscribers, no ownership | **EventBus** | Autoload that imports half the game |
| One scene's private wiring | **Scene-local node** + `%UniqueName` | Global bus for parent→child calls |

### 四、Autoload 使用边界

**Good:** Game/Audio/Save managers, SceneTransitioner, global score/inventory, cross-scene EventBus.

### 什么不进
- **NEVER store highly localized, scene-specific data in AutoLoads** — This creates "God Objects" and introduces global side effects that are hard to debug.
- **NEVER use an Autoload for pure data containers** — If you don't need `_process()` or signals, use a `static var` in a `class_name` script instead.
- **NEVER use AutoLoads for UI elements that aren't global** — Popups that only exist in one level should be in that level, not a global singleton.
- **NEVER use monolithic Autoloads** — Avoid managers that hold visual node references; keep singletons focused on pure data or RefCounted delegation.

### 生命周期红线
- **NEVER create circular dependencies between Singletons** — If A needs B and B needs A, Godot will hang during the splash screen.
- **NEVER free an Autoload node manually** — Removing a singleton from the root can leave dangling references that crash the engine.

### 本项目约定（GameManager / SaveManager / EventBus）
- Buses emit past-tense events (`item_obtained`, `quest_completed`); mutable run state (inventory, settings) lives in state-holder Autoloads — not on the bus.
- Autoloads sit at the root — the ultimate "top". They never call down into the active scene; scenes connect to Autoload signals or query Autoload state.
- SaveManager 拥有持久化与唯一存档路径；GameManager 只做编排，不得自建第二套存档读写。
- Boot 顺序与 `_ready` / `_init` 时机规则见 `references/architecture.md`；新增全局服务先过 §三 所有权决策树。

## 何时读哪个 references

| 场景 | 文件 |
|------|------|
| 场景切换/异步加载/loading 屏、autoload 通信细节、依赖注入取舍 | `references/architecture.md` |
| 加密存档、背包/道具、经济/资源循环、任务/签到/成就 | `references/gameplay-systems.md` |
| 挂机生产循环、成长曲线、大数处理、离线收益 | `references/idle-loop.md` |
| 设计数据入口/存档结构/时间处理时的联机预留原则 | `references/multiplayer-readiness.md` |
| 布局容器、主题风格、RichTextLabel、UI 组合、Tween、音频总线与音量 | `references/ui-mobile.md` |
| 触屏/竖屏/安全区、移动渲染与性能、Android 导出与命令行打包 | `references/mobile-build.md` |

## 来源映射

| 本技能章节 | 蒸馏自 |
|------|--------|
| 核心规范·目录/命名 | godot-project-foundations |
| 核心规范·GDScript 硬规则 | godot-gdscript-mastery |
| 核心规范·信号架构 | godot-signal-architecture |
| 核心规范·Autoload 边界 | godot-autoload-architecture |
| architecture.md | godot-scene-management、godot-autoload-architecture |
| gameplay-systems.md | godot-save-load-systems、godot-inventory-system、godot-economy-system、godot-quest-system |
| idle-loop.md | godot-genre-idle-clicker |
| multiplayer-readiness.md | godot-adapt-single-to-multiplayer、godot-genre-idle-clicker |
| ui-mobile.md | godot-ui-containers、godot-ui-theming、godot-ui-rich-text、godot-composition-apps、godot-tweening、godot-audio-systems |
| mobile-build.md | godot-platform-mobile、godot-export-builds |

原始库：https://github.com/thedivergentai/gd-agentic-skills（Godot 4.7+）。需求大改或上游大版本更新时重跑 /godot-maker 重新蒸馏。
