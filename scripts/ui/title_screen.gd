class_name TitleScreen
extends Control
## 标题 / 开场七页剧情 / 角色创建（对应原版启动窗口流程）。
## 只做接线：页面内容来自 router.page，事件统一走 router.handle。

var _router: EventRouter
var _view: PageView
var _scroll: ScrollContainer
var _input_row: HBoxContainer
var _name_edit: LineEdit
var _safe_frame: SafeAreaFrame


func _init(router: EventRouter) -> void:
	_router = router


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_router.handle("story:-1")
	_render()
	# 检查更新是异步的：结果回填 router.page 后重渲染当前页
	_router.page_changed.connect(_render)


func _build_ui() -> void:
	# 安全区框占满全屏：顶部输入行等内容随它的 insets 避开刘海/挖孔与导航条，
	# 设计边距仍保留在原 margin 上（桌面无刘海时 insets=0，布局零变化）
	_safe_frame = SafeAreaFrame.new()
	_safe_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_safe_frame)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_bottom", 40)
	_safe_frame.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)

	# 名字输入行放在页面区上方：不依赖窗口高度，也不会被移动端软键盘遮住
	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 12)
	_input_row.visible = false
	vbox.add_child(_input_row)

	var hint := Label.new()
	hint.text = "角色名:"
	_input_row.add_child(hint)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "请输入创建角色名"
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(0, 56)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_color_override("font_placeholder_color", Color(0.72, 0.72, 0.72))
	_input_row.add_child(_name_edit)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 触摸滚动修复点（契约 docs/trade-spec.md §8）：隐藏滚动条但保留触摸拖动滚动
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	vbox.add_child(_scroll)

	_view = PageView.new()
	_scroll.add_child(_view)
	_view.link_activated.connect(_on_link)


func _on_link(event: String) -> void:
	if event.begins_with("create:"):
		_router.handle(event, _name_edit.text)
	else:
		_router.handle(event)
	_input_row.visible = _router.input_mode == "char_name"
	if _input_row.visible:
		_name_edit.grab_focus()
	_render()


func _render() -> void:
	_view.show_page(_router.page)
	_scroll_top()


func _scroll_top() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = 0
