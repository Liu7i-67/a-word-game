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
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("normal_font_size", 23)
	add_theme_font_size_override("bold_font_size", 25)
	add_theme_font_size_override("italics_font_size", 23)
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
