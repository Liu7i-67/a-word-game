# 架构深潜：场景管理与 Autoload 通信

> 何时读本文件：实现场景切换 / loading 屏 / 异步加载，或设计 Autoload 全局状态、跨场景信号通信、依赖注入时阅读。命名约定、GDScript 陷阱、Signal Up / Call Down 基本规则见 SKILL.md「核心规范」，此处不再重复。

## 一、场景管理

### NEVER Do in Scene Management
- **NEVER load large scenes synchronously** — `load("res://large_scene.tscn")` on the Main Thread causes "hiccups" or full freezes during level transitions. Use `ResourceLoader.load_threaded_request()` for async loading with a progress bar.
- **NEVER modify the SceneTree from a background thread** — Strictly use `call_deferred()` for thread-to-main-thread synchronization.
- **NEVER use `get_tree().change_scene_to_file()` for transient state** — This method purges the current scene and all its local variables. Use an **Autoload (Singleton)** or a persistent 'Game' node to store state across levels.
- **NEVER instance 100+ identical nodes per frame** — Use **Object Pooling**. Constant `instantiate()` and `queue_free()` calls spike CPU and trigger the Garbage Collector too often.
- **NEVER use `change_scene` to "Reset" a level** — It reloads everything from disk. For a quick respawn, just reset the variables and move the player to the start position.
- **NEVER use `_process()` for precise input** — Tied to visual framerate. Strictly use `_unhandled_input()` to capture exact, frame-independent events.

### 决策树：如何切换内容
| Goal | Prefer |
|------|--------|
| Full level swap with progress UI | Threaded load → swap when `THREAD_LOAD_LOADED` |
| Fade / wipe around a swap | Transition Autoload wraps the manager |
| Keep world; show pause / map / inventory / settings | Additive UI layer (do **not** `change_scene`) |
| Survive scene purge | Autoload / persist group — not locals |
| Quick respawn | Reset state + teleport — **not** `change_scene` |

### 异步加载循环（loading 屏核心，必须处理失败分支）
```gdscript
func load_scene_async(path: String) -> void:
    ResourceLoader.load_threaded_request(path)
    var progress := []
    while true:
        var status := ResourceLoader.load_threaded_get_status(path, progress)
        if status == ResourceLoader.THREAD_LOAD_LOADED:
            get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(path))
            break
        if status == ResourceLoader.THREAD_LOAD_FAILED:
            push_error("Failed: " + path)
            break
        await get_tree().process_frame
```
- `progress[0]`（0.0–1.0）驱动进度条；loading 屏 = 常驻 CanvasLayer + ProgressBar，swap 完成后再隐藏。
- Fade transition：CanvasLayer Autoload 用 `await $AnimationPlayer.animation_finished` 包住 `change_scene_to_file`，先 fade_out 后 fade_in。

### 其他要点
- 保留世界、叠加背包 / 设置 / 暂停等浮层 → additive UI layer 挂在常驻 UI root 下，绝不 `change_scene`。
- 跨场景状态（run state、inventory、settings）放 Autoload state holder，不要存场景局部变量（会被 purge）。
- 背景预载：start `load_threaded_request` during gameplay; transition only when loaded（hitch avoidance）。
- 小型 UI 场景可 `preload()` 常量缓存 PackedScene；大场景一律 threaded load。
- Autoload 拥有切换时用 deferred free + root 所有权管理（safe switcher 模式），不要立即 free 当前场景。
- 场景切换前后经总线重新接线或重连信号，避免留下指向已释放节点的 ghost listener。
- Orphan audit：`Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) > 0` means leaked refs still hold freed nodes → `Node.print_orphan_nodes()`。
- Cleanup before transition: stop timers; `queue_free()` on a root is recursive in Godot 4 — no manual child loops.
- `get_tree().reload_current_scene()` — expensive full disk reload; use only when intentional.

## 二、Autoload 全局状态与信号通信

### Boot 顺序与生命周期
- Autoloads initialize **top → bottom** in Project Settings. Upper singletons must not call lower ones in `_ready()`. Move dependents down the list.
- If `SaveManager` (pos 1) calls `PlayerManager` (pos 5) in `_ready()`, it will receive a null reference. Always move managers with dependencies to the bottom of the list.
- **NEVER access AutoLoads in `_init()`** — AutoLoads are initialized sequentially. Accessing one in `_init()` may find a null reference.
- **NEVER modify a Singleton's size or children in `_ready()`** — If multiple Singletons refer to each other's trees during boot, it can cause layout/sorting errors.
- **NEVER assume `get_tree().current_scene` is accurate in `_ready()`** — In Autoloads, the active scene might still be initializing. Access it via `get_tree().root.get_child(-1)`.
- **NEVER skip `process_mode` configuration** — If your global console or music manager needs to work while the game is paused, set `process_mode = PROCESS_MODE_ALWAYS`.

### 惰性初始化（Autoload 常驻，勿在 `_ready()` 做重活）
```gdscript
var _initialized: bool = false

func initialize() -> void:
    if _initialized:
        return
    _initialized = true
    # Heavy setup here
```

### 通信约定
- Prefer signals for state changes; do not reach into Autoload children from gameplay scenes.
- 事件总线只发 past-tense 类型化事件，AutoLoad 中的声明形态：`signal level_completed(level_number: int)`；描述性命名 `enemy_defeated(enemy_type: String)` not `done()`。
- Group related signals（如 inventory / quest / achievement 各成一组）；出现 A signals B、B signals back to A 的环时，用 mediator（父节点或 Autoload）打断。

### 依赖注入取舍
- 标准 Autoload 必须是 `Node`，带 SceneTree / 内存开销；纯数据或非节点服务改用 `Engine.register_singleton()` 注册轻量 `RefCounted` 服务。
- ServiceLocator Autoload 置于加载列表最顶端；`_exit_tree` 中必须 `Engine.unregister_singleton` 防悬空引擎单例；消费方用 `Engine.get_singleton(&"Name")` O(1) 查找。
- 本项目取舍：起步阶段直接用少量 Node Autoload（GameManager / SaveManager / EventBus）+ 类型化信号即可；Service Locator 仅当服务需要按需注册 / 可替换（如未来联机层替换本地实现）时再引入，现在不写联机代码。
- Health checks（debug / CI）: `assert()` 验证 Autoload 节点存在（`get_tree().root.get_node_or_null("SaveManager")`）、`Engine.has_singleton(&"X")` 验证动态注册、`is_instance_valid()` 验证内存安全；boot 时或测试套件中运行，防止状态回归。

<!-- 来源映射
- 场景管理: godot-scene-management（SKILL.md + references/scene-patterns-deep.md）
- NEVER modify the SceneTree from a background thread / NEVER use _process() for precise input: godot-project-foundations（SKILL.md）
- Boot 顺序与生命周期 / 惰性初始化 / 依赖注入取舍: godot-autoload-architecture（SKILL.md + references/expert-patterns.md、autoload-patterns.md）
- 通信约定（类型化事件 / 命名 / 分组 / mediator 打断环）: godot-signal-architecture（SKILL.md + references/implementation-patterns.md）
-->
