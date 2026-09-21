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
var _safe_frame: SafeAreaFrame
var _last_click_ms := -1000000

## 自动战斗：激活后循环模拟真人点击（首怪→攻击→继续→返回游戏→再战），
## 体力低于阈值 / 场景无怪 / 战败 / 离开场景时自动终止
var _auto_btn: Button
var _auto_active := false
var _auto_scene := ""
var _auto_phase := ""


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
	# 安全区框占满全屏：内容随它的 insets 避开刘海/挖孔与手势导航条，
	# 设计边距仍保留在原 margin 上（桌面无刘海时 insets=0，布局零变化）
	_safe_frame = SafeAreaFrame.new()
	_safe_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_safe_frame)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 28)
	_safe_frame.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# 顶栏：昵称 · 体力条 · 铜贝
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	vbox.add_child(top)

	_name_label = Label.new()
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 46)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_hp_bar)

	_hp_text = Label.new()
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_text.add_theme_font_size_override("font_size", 23)
	_hp_bar.add_child(_hp_text)

	_copper_label = Label.new()
	_copper_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_copper_label)

	# 导航按钮行
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 14)
	vbox.add_child(nav)
	for label: String in MENU_EVENTS:
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(0, 58)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_menu.bind(MENU_EVENTS[label]))
		nav.add_child(btn)
	var save_btn := Button.new()
	save_btn.text = "存档"
	save_btn.custom_minimum_size = Vector2(0, 58)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_manual_save)
	nav.add_child(save_btn)
	_auto_btn = Button.new()
	_auto_btn.text = "自动战斗"
	_auto_btn.custom_minimum_size = Vector2(0, 58)
	_auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_btn.pressed.connect(_on_auto_toggle)
	nav.add_child(_auto_btn)

	# 页面区（禁用横向滚动：富文本按容器宽度换行）
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 触摸滚动修复点（契约 docs/trade-spec.md §8）：隐藏滚动条但保留触摸拖动滚动
	#（市场货单等长页面移动端可拖动浏览）；真机效果待用户验证
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vbox.add_child(_scroll)
	_view = PageView.new()
	_scroll.add_child(_view)
	_view.link_activated.connect(_on_link)

	# 轻提示（点击太快了 / 存档已保存）。SafeAreaFrame 是容器会接管子节点布局，
	# 因此 toast 挂在它下面的整幅普通 Control 上：锚点定位保持原视觉位置，
	# 但相对的是已扣除安全区的区域，底部不再被虚拟导航栏盖住。
	var toast_holder := Control.new()
	toast_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_frame.add_child(toast_holder)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# 垂直方向必须显式上生长：默认 END 会把文字向下排到安全区外（桌面甚至出屏）
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_top = -56
	_toast.offset_bottom = -56
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_color", Color(1, 1, 1))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_holder.add_child(_toast)

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


# ---------- 自动战斗 ----------

func _on_auto_toggle() -> void:
	if _auto_active:
		_stop_auto("")
		return
	if _too_fast():
		return
	if _player.hp_cur * 100 < _player.max_hp() * Rules.auto_stop_hp_pct():
		_show_toast("当前体力过低，不支持自动战斗")
		return
	if _router.scene_first_monster() == "":
		_show_toast("当前场景无可战斗对象")
		return
	_auto_active = true
	_auto_scene = _player.location
	_auto_phase = ""
	_auto_btn.text = "战斗ing"
	_auto_run()


func _stop_auto(message: String) -> void:
	_auto_active = false
	_auto_btn.text = "自动战斗"
	if message != "":
		_show_toast(message)


## 自动战斗循环：逐步模拟真人点击，每步间隔 auto_tick_ms。
## 战斗中点「攻击」→ 胜利页点「继续」→ 战利品页点「返回游戏」→ 回场景再战。
func _auto_run() -> void:
	while _auto_active:
		if not is_inside_tree():
			return
		if _player.location != _auto_scene:
			_stop_auto("已离开战斗场景，自动战斗结束")
			return
		if _player.hp_cur * 100 < _player.max_hp() * Rules.auto_stop_hp_pct():
			_stop_auto("体力低于30%，自动战斗结束")
			return
		var combat := _router.combat
		if combat != null and not combat.finished:
			_router.handle("attack")
		elif combat != null and combat.finished and combat.won:
			if _auto_phase == "reward":
				_router.handle("combat_leave")
				_auto_phase = ""
			else:
				_router.handle("combat_reward")
				_auto_phase = "reward"
		elif combat != null:
			# 战败：已被好心人救回城里，停止挂机等玩家自己恢复
			_stop_auto("战斗失败，自动战斗结束")
			return
		else:
			_auto_phase = ""
			var monster_id := _router.scene_first_monster()
			if monster_id == "":
				_stop_auto("当前场景无可战斗对象，自动战斗结束")
				return
			_router.handle("fight:" + monster_id)
		_after_event()
		await get_tree().create_timer(Rules.auto_tick_ms() / 1000.0).timeout


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
