何时读本文件：本项目（Android 竖屏 720×1280、触屏点击、纯 Control/UI、文本密集）里写或改任何 UI 时读——竖屏布局容器、Theme/StyleBox、RichTextLabel/BBCode、Control 编排、Tween 反馈动效、设置菜单音量。

## 1. 布局与容器

| 需求 | 用 |
|------|----|
| 列数随宽度变化（背包格子） | `GridContainer` + 响应式改 `columns` |
| 标签/chip 换行 | `HFlowContainer` |
| 上千滚动行 | Virtual List Pooling（小 Control 池 + 占位高度），非原始子节点 |
| 日志/文本自动滚底 | `ScrollContainer`（注意下方同帧陷阱） |

NEVER Do in UI Containers:
- NEVER ignore **`mouse_filter`** properties; strictly set to `PASS` or `IGNORE` on overlay containers to prevent them from blocking clicks to underlying buttons.
- NEVER instantiate thousands of nodes in a `ScrollContainer`; strictly use **Virtual List Pooling** for O(1) rendering performance.
- NEVER manually calculate card dimensions for responsive grids; strictly use an **`AspectRatioContainer`** to lock proportions (e.g., 2:3 ratio) while allowing parent containers to handle scaling.
- **NEVER manually set child `position` or `size` in a Container** — Containers override child transforms during `queue_sort()`. Use `custom_minimum_size` or `size_flags` instead.
- **NEVER forget `size_flags` for expansion** — Default is `SIZE_SHRINK_BEGIN`. Children will stay tiny unless you set `SIZE_EXPAND_FILL` for responsive containers.
- **NEVER use `GridContainer` without setting `columns`** — Default is 1, creating a simple vertical list.
- **NEVER nest containers too deeply (10+ levels)** — Heavy nesting causes layout recalculation spikes. Replace intermediate containers with Anchor Layouts for static padding.
- **NEVER skip separation overrides** — Default theme separation is often too tight. Use `add_theme_constant_override("separation", value)` for professional breathing room.
- **NEVER use `ScrollContainer` without a minimum size** — Without it, the container may collapse to zero or expand infinitely, breaking the scroll mechanism.
- **NEVER scroll to a new child on the same frame it was added** — The layout hasn't updated yet. You MUST `await get_tree().process_frame` before setting `scroll_vertical`.
- **NEVER use `GridContainer` for responsive wrapping** — Use `HFlowContainer` if you want items to wrap based on width. GridContainer enforces a strict column count.
- **NEVER animate `position` directly inside a container** — Use `Tween` on `custom_minimum_size` to smoothly "push" siblings during transitions.

竖屏适配最短示例：

```gdscript
$MarginContainer.set_anchors_preset(Control.PRESET_FULL_RECT)
$MarginContainer.add_theme_constant_override("margin_left", 20)
$VBoxContainer.add_theme_constant_override("separation", 10)
button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
```

## 2. 主题与风格

Theme 归属决策：全局观感 → Project Settings → GUI → Theme（Theme 编辑器里做，别逐节点覆盖）；单个 Control 不同 → 该节点 `add_theme_*_override`（仅局部）；按钮/面板子类型 → `theme_type_variation`；运行时改色 → 先 `stylebox.duplicate()` 再改。

NEVER Do in UI Theming:
- **NEVER create StyleBox in `_ready()` for many nodes** — Instantiating `StyleBoxFlat.new()` 100 times creates 100 unique objects. Use a Theme resource for shared heritage.
- **NEVER forget theme inheritance** — Parent themes are ignored if a child has its own theme. Apply themes at the root and use `theme_type_variation` for specific overrides.
- **NEVER hardcode colors in StyleBox** — Use `theme.get_color()` to maintain a single source of truth for your palette.
- **NEVER use `add_theme_override` for global styles** — This is brittle. Define styles in a Theme resource for automatic propagation across the project.
- **NEVER modify theme resources during `_draw()` OR `_process()`** — Frequent layout recalculations will severely degrade performance.
- **NEVER use standard `set()` for theme properties** — Calling `node.set("font_color", red)` fails. You MUST use the dedicated `add_theme_color_override()` API.
- **NEVER use `expand_margin_*` to increase clickable area** — It only expands the VISUAL bounds. Use `content_margin_*` on the StyleBox or adjust the Control's size to ensure input works.
- **NEVER define StyleBoxes as local variables inside `_draw()`** — They will be garbage collected before the RenderingServer can finish drawing them. Store at class level.
- **NEVER duplicate scenes/themes just to change one color** — Use `theme_type_variation` to create lightweight derived styles (e.g. "DangerButton") within the same Theme.
- **NEVER confuse Theme items with Control overrides** — `add_theme_*_override` beats Theme resource items on that node only; a child Control with its own `theme` still blocks parent cascade. Clear with `remove_theme_*_override` when swapping roots.

要点：变体在 Theme 编辑器建 Type Variation（Base Type 设为 Button，只覆写差异项，代码 `node.theme_type_variation = &"DangerButton"`）；调色板做进 `.theme` 的自定义 `Palette` 类型，脚本用 `ThemeDB.get_project_theme()` 读取，避免 UI 与主题漂移；换肤（日/夜间）只需给根 Control 赋新 Theme 资源，自动级联；UI 图标可打包 `AtlasTexture` 减少绘制状态切换。

```gdscript
var style := StyleBoxFlat.new()
style.bg_color = Color.DARK_BLUE
style.set_corner_radius_all(5)  # 统一圆角用它，别填四个独立字段
$Button.add_theme_stylebox_override("normal", style)
# 运行时要改共享主题的 StyleBox：必须先 style = style.duplicate() 再改
```

## 3. 文本展示（RichTextLabel/BBCode）

NEVER Do (Expert UI Rules):
- **NEVER use complex BBCode in tight loops** — Parsing a 10,000 character string with 500 tags every frame will tank performance. Cache your formatted strings.
- **NEVER forget to register Custom Effects** — Writing the script isn't enough. You MUST add the instance to `RichTextLabel.custom_effects` list via Inspector or `install_effect()`.
- **NEVER use absolute pixel sizes in [img]** — `[img width=128]` fails on higher resolutions. Godot 4.7: use `width_unit` / `height_unit` + `RichTextLabel.ImageUnit`, scale with line height.
- **NEVER use [url] without visual feedback** — If the text doesn't change color on hover or the cursor doesn't change, players won't know it's clickable.
- NEVER hardcode layout logic into strings; strictly use **BBCode Tables** and **Alignment Tags** to ensure text structures remain flexible.
- NEVER animate text typewriter effects by modifying the `text` or `bbcode` string frame-by-frame; strictly use **`visible_ratio`** or **`visible_characters`** to avoid expensive parsing overhead and flickering.
- NEVER use standard bitmap fonts for large titles or dynamic UI; strictly use **MSDF** fonts to ensure perfectly crisp outlines and scaling at any resolution.
- **NEVER perform heavy logic inside `meta_clicked`** — This signal is on the Main Thread. Use it to emit a command and handle processing asynchronously if needed.
- **NEVER use `visible_ratio` for pausing typewriter** — `visible_ratio` is unreliable for per-character logic. Use `visible_characters` and explicit character indexing.
- **NEVER allow unfiltered user input in Chat Labels** — A user could type `[img]huge_image_path[/img]` or `[color=transparent]` to break your UI. Pipe every user-generated string through a BBCode sanitizer before assigning `text`.

打字机 API 决策：整行淡入/整体揭示 → `visible_ratio` + Tween（内联即可）；需要 `[pause]`/`[speed]` 等逐字暂停/变速事件标签 → `visible_characters` + 字符索引器。

```gdscript
func reveal_fade(label: RichTextLabel, new_text: String, duration: float) -> void:
    label.text = new_text
    label.visible_ratio = 0.0
    create_tween().tween_property(label, "visible_ratio", 1.0, duration)

func _on_meta_clicked(meta: Variant) -> void:
    emit_signal("command_requested", meta)  # 只发命令，重逻辑异步处理
```

要点：自定义 BBCode 标签（如 `[relic color=…]`）→ `@tool extends RichTextEffect`，脚本里 `var bbcode = "relic"`，在 `_process_custom_fx(char_fx)` 改 `char_fx.offset/color`，并注册进 `custom_effects`；描边用 `add_theme_color_override("font_outline_color", …)` + `add_theme_constant_override("outline_size", 4)`，别把样式烤进 BBCode 字符串；`$RichTextLabel.bbcode_enabled = true` 后 `text` 里才能用 BBCode。

## 4. UI 组合模式（Control-heavy 编排）

规则：每个界面根脚本（如 `SettingsMenu.gd`）是 Orchestrator——业务逻辑 0%、状态接线 100%，职责是听组件信号、调组件方法（通信方向遵循全局 Signal Up / Call Down，此处不重复）。写组件前先做 Rock Test："If I attached this script to a literal rock, would it still function?"（通过 = 上下文无关；失败 = 去 `$` 抓兄弟节点）。根是 Has-A 背包（组合组件），不做继承链。依赖注入用 `@export var auth: AuthComponent`（Inspector / `%UniqueName`），**NEVER** brittle `get_node("Path/To/Child")`；组件保持无状态，由 Orchestrator 传参，组件不抓兄弟 Control。

NEVER Do (Expert Architectural Rules):
- **NEVER use get_parent() to fetch data** — Inject via `@export` or function args.
- **NEVER put business logic in the Orchestrator** — Only `_on_signal` delegators.
- **NEVER store global state in individual components** — Shared Context Resource or Autoload.
- **NEVER skip signal cleanup** — Disconnect on exit / use CONNECT_ONE_SHOT where appropriate.
- **NEVER let Logic know about Visuals** — Emit; VLS / Orchestrator plays animations and applies Theme.

```gdscript
# settings_menu.gd — 只接线，不写业务
extends Control
@export var form_logic: Node
func _ready() -> void:
    form_logic.settings_valid.connect(_on_settings_valid)
    form_logic.settings_invalid.connect(_on_settings_invalid)
func _on_settings_invalid(field: StringName) -> void:
    var target := get_node_or_null("%" + String(field))  # Orchestrator 独占 grab_focus
    if target is Control: target.grab_focus()
```

要点：存档/主题走组件而非表单控件本体——持久化组件 `add_to_group("Saveable")` + `get_save_data()`，Theme/StyleBox 变更由 Orchestrator 在逻辑成功信号后向下调用主题组件；VLS（Logic-Visual Syncer）：逻辑只 `emit state_changed`，动效/Theme 由独立 syncer 播放，逻辑永不调 `AnimationPlayer.play()`；轻量非 Node 服务用 `Engine.register_singleton()`，避免堆 Autoload；面板模块多时 Orchestrator 建私有 Dictionary 注册表一次性登记子组件（仍禁止兄弟直连）。

## 5. Tween 动效

决策：一次性 UI juice（弹窗、按钮反馈、**数字跳动/score count**）→ `create_tween()`；重触发（连点按钮）→ kill 后重建；暂停菜单/`Engine.time_scale == 0` 时的菜单动效 → `set_ignore_time_scale(true)`；多轨道可剪辑动画 → AnimationPlayer。

NEVER Do in Tweening:
- **NEVER instantiate a Tween using `Tween.new()`** — Always use `create_tween()` or `get_tree().create_tween()`.
- **NEVER attempt to reuse a finished Tween** — Single-use; recreate to replay.
- **NEVER manually instantiate `PropertyTweener` or `CallbackTweener`** — Only via parent Tween methods.
- **NEVER create an infinite loop containing only 0-duration animations** — Freezes the engine.
- **NEVER use multiple Tweens to animate the same property simultaneously** — `kill()` the old reference first.
- **NEVER use linear interpolation for UI/Juice** — Prefer `EASE_OUT + TRANS_QUAD` or `EASE_IN_OUT + TRANS_CUBIC`.
- **NEVER create tweens in `_process` without guards** — Creating 60 tweens per second will crash the app.
- **NEVER skip `bind_node(self)` for non-global tweens** — Binding ensures death with the node.
- **NEVER use 0-duration tweens for state changes** — Set the property directly.
- **NEVER forget to call `chain()` when returning from `set_parallel(true)`**.

生命周期黄金路径（连点安全的重触发模板）：

```gdscript
var _tween: Tween

func animate_to(pos: Vector2) -> void:
    if _tween and _tween.is_valid():
        _tween.kill()
    _tween = create_tween().bind_node(self)
    _tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
    _tween.tween_property(self, "position", pos, 0.35)
```

要点：数字跳动（非属性值，如分数文本）用 `tween_method` 插值写入 Label；容器内 Children 增删/重排的入场用单条 Tween 顺序 stagger，且别直接动 `position`（见第 1 节，动 `custom_minimum_size`）；多属性并行动画用 `set_parallel(true)`，返回顺序执行记得 `chain()`；手感参数（时长/缓动）存 Resource，统一分发。

## 6. 音频总线与设置音量

NEVER Do (Mixing & Buses):
- **NEVER set bus volume with linear values** — `set_bus_volume_db()` is logarithmic. Use `linear_to_db()` for sliders OR everything will sound too loud until the last 5%.
- **NEVER skip 'Bus Routing'** — Playing music on the 'SFX' bus makes volume menus useless. Strictly route every player to its dedicated sub-bus (Music, SFX, UI, Voice).
- **NEVER use 'Master' for gameplay sounds** — Dedicate Master to final limiting. Route all gameplay to sub-groups so you can mute/duck categories.

总线结构：`Master（只挂 Limiter）→ Music / SFX / UI / Voice`；本项目音乐/UI 音效一律用普通 `AudioStreamPlayer`（非定位、最快），各自路由到专属子总线。

```gdscript
# BAD
AudioServer.set_bus_volume_db(music_idx, 0.5)
# GOOD（设置菜单滑条 0.0~1.0 → dB）
AudioServer.set_bus_volume_db(music_idx, linear_to_db(0.5))
```

要点：设置菜单音量按 bus 名找索引：`AudioServer.get_bus_index("Music")`，静音用 `AudioServer.set_bus_mute()`；把每个 bus 的音量/静音一起持久化到存档，重启后恢复，别重写总线布局；切 BGM 不硬切，用 0.5–1.0s Tween 交叉淡化；别为一次性短音效 `AudioStreamPlayer.new()` + `queue_free()`（约 3600 节点/分钟 + 帧尖峰），预分配轮询池，同帧重复音效用 Limiter/上限防削波；排查无声：stream 未赋值？bus 被静音？`volume_db < -60` 等于无声。

<!-- 来源映射
- 布局与容器: godot-ui-containers（SKILL.md NEVER 列表/决策树 + references/container-layout-recipes.md）
- 主题与风格: godot-ui-theming（SKILL.md NEVER 列表/决策树/模式 1-3 + references/theme-authoring-recipes.md）
- 文本展示: godot-ui-rich-text（SKILL.md NEVER 列表/Reveal API/模式 1-3 + references/bbcode-tag-catalog.md）
- UI 组合模式: godot-composition-apps（SKILL.md Orchestrator/NEVER/Saveable + references/app-orchestrator-examples.md）
- Tween 动效: godot-tweening（SKILL.md 决策树/NEVER/Golden Path + references/tween-recipes-and-gotchas.md）
- 音频总线与设置音量: godot-audio-systems（SKILL.md Mixing & Buses/Bus architecture + references/audio-pooling-and-buses.md；3D 空间音频、作曲/交互音乐已按画像剔除）
-->
