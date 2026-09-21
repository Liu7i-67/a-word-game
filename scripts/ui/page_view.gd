class_name PageView
extends RichTextLabel
## 超文本页面视图（对应原版「简单超文本框」）：
## BBCode 渲染 + [url] 点击转发；换页时短暂淡入，自动滚回顶部。

signal link_activated(event: String)

var _fade_tween: Tween


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	selection_enabled = false
	scroll_active = false
	context_menu_enabled = false
	focus_mode = Control.FOCUS_NONE
	# 触摸滚动修复点（契约 docs/trade-spec.md §8）：默认 STOP 会吞掉触摸拖动，
	# 改为 PASS 让拖动事件穿透到外层 ScrollContainer；[url] 点击仍走 meta_clicked。
	# 无真机验证，最终以用户真机滚动表现为准。
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("normal_font_size", 26)
	add_theme_font_size_override("bold_font_size", 29)
	add_theme_font_size_override("italics_font_size", 26)
	add_theme_constant_override("line_separation", 10)
	meta_clicked.connect(_on_meta_clicked)


## 展示新页面：整体淡入（visible_ratio，避免逐帧改文本重解析）
func show_page(bb: String) -> void:
	text = bb
	visible_ratio = 0.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().bind_node(self)
	_fade_tween.tween_property(self, "visible_ratio", 1.0, 0.12)


func _on_meta_clicked(meta: Variant) -> void:
	link_activated.emit(str(meta))
