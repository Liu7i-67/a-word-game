class_name GameScreen
extends Control
## 游戏主界面：顶栏（昵称/体力/铜贝）+ 导航按钮 + 超文本页面区（对应原版主渲染区）。
## 业务逻辑全部在 EventRouter / PlayerCore，本类只负责渲染与转发点击。

const MENU_EVENTS := {"状态": "status", "物品": "items", "地图": "map"}

var _router: EventRouter
var _player: PlayerCore

var _view: PageView
var _scroll: ScrollContainer
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_text: Label
var _copper_label: Label
var _toast: Label
var _toast_tween: Tween
var _last_click_ms := -1000000


func _init(router: EventRouter, player: PlayerCore) -> void:
	_router = router
	_player = player


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_player.hp_changed.connect(_on_stats_changed)
	_player.copper_changed.connect(_on_stats_changed)
	_player.gold_changed.connect(_on_stats_changed)
	_player.leveled_up.connect(_on_leveled_up)
	_router.open_start_scene()
	_render()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# 顶栏：昵称 · 体力条 · 铜贝
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vbox.add_child(top)

	_name_label = Label.new()
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 36)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_hp_bar)

	_hp_text = Label.new()
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_text.add_theme_font_size_override("font_size", 20)
	_hp_bar.add_child(_hp_text)

	_copper_label = Label.new()
	_copper_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_copper_label)

	# 导航按钮行
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	vbox.add_child(nav)
	for label: String in MENU_EVENTS:
		var btn := Button.new()
		btn.text = label
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_menu.bind(MENU_EVENTS[label]))
		nav.add_child(btn)
	var save_btn := Button.new()
	save_btn.text = "存档"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_manual_save)
	nav.add_child(save_btn)

	# 页面区（禁用横向滚动：富文本按容器宽度换行）
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	_view = PageView.new()
	_scroll.add_child(_view)
	_view.link_activated.connect(_on_link)

	# 轻提示（点击太快了 / 存档已保存）
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_bottom = -56
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

	_refresh_topbar()


# ---------- 事件入口 ----------

func _on_link(event: String) -> void:
	if _too_fast():
		return
	_router.handle(event)
	_after_event()


func _on_menu(event: String) -> void:
	if _too_fast():
		return
	_router.handle(event)
	_after_event()


func _on_manual_save() -> void:
	_save()
	_show_toast("存档已保存")


func _too_fast() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_click_ms < Rules.click_cooldown_ms():
		_show_toast("点击太快了")
		return true
	_last_click_ms = now
	return false


func _after_event() -> void:
	if _router.needs_save:
		_save()
		_router.needs_save = false
	_refresh_topbar()
	_render()


func _save() -> void:
	_player.write_to(SaveManager.data)
	SaveManager.save_game()


# ---------- 渲染 ----------

func _render() -> void:
	_view.show_page(_router.page)
	_scroll_top()


func _scroll_top() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = 0


func _refresh_topbar() -> void:
	_name_label.text = "%s Lv.%d" % [_player.nickname, _player.level]
	_hp_bar.max_value = _player.max_hp()
	_hp_bar.value = _player.hp_cur
	_hp_text.text = "体力 %d/%d" % [_player.hp_cur, _player.max_hp()]
	_copper_label.text = "铜贝 %d" % _player.copper


func _on_stats_changed(_a: int = 0, _b: int = 0) -> void:
	_refresh_topbar()


func _on_leveled_up(new_level: int) -> void:
	_show_toast("升级了！当前 %d 级" % new_level)


func _show_toast(message: String) -> void:
	_toast.text = message
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween().bind_node(self)
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
