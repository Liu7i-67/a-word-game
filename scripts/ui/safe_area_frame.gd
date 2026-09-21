class_name SafeAreaFrame
extends MarginContainer
## 全面屏 / 水滴屏安全区适配框：通过自身四边 margin 把子内容从
## 顶部刘海/挖孔与底部手势虚拟导航条区域向内收，防止内容被遮挡。
##
## 坐标换算：DisplayServer.get_display_safe_area() 返回的是窗口像素坐标，
## 而本项目 stretch=canvas_items + aspect=expand 下窗口像素 ≠ canvas 像素，
## 必须经 get_window().get_final_transform().affine_inverse() 把安全区矩形
## 映射回 canvas 坐标，再与 get_viewport().get_visible_rect() 求内边距。
## 依据：Viewport.get_screen_transform()（canvas → 屏幕像素）=
## 窗口位置 × get_final_transform()，即 final_transform 就是
## canvas 坐标 → 所在窗口像素坐标 的映射，其逆变换即窗口像素 → canvas。
##
## 调试模拟：命令行 user args 出现 --sim-insets=左,上,右,下（单位为
## 720×1280 canvas 像素，如 --sim-insets=0,90,0,48）时忽略系统值直接采用，
## 便于无真机截图验证；也可在运行中调用 set_simulated_insets()（走查复用，
## 免重启进程）。桌面 / 无刘海环境 insets 恒为 0，布局零变化。

const NO_INSETS := Vector4(-1, -1, -1, -1)  ## 哨兵：未启用模拟 insets
const SIM_ARG_PREFIX := "--sim-insets="

var _sim_insets := NO_INSETS


static func parse_sim_insets(args: PackedStringArray) -> Vector4:
	## 从命令行 user args 解析 --sim-insets=左,上,右,下；未提供返回 NO_INSETS。
	for arg: String in args:
		if not arg.begins_with(SIM_ARG_PREFIX):
			continue
		var parts := arg.trim_prefix(SIM_ARG_PREFIX).split(",")
		if parts.size() != 4:
			push_warning("SafeAreaFrame: %s 需为逗号分隔的 4 个数值，已忽略" % arg)
			break
		return Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
	return NO_INSETS


static func compute_insets(content_size: Vector2, safe_rect: Rect2) -> Vector4:
	## 纯函数：由 canvas 内容尺寸与 canvas 坐标安全区矩形求四边内收量。
	## 返回 x=左 y=上 z=右 w=下；负值（安全区越界或大于内容）一律钳到 0。
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return Vector4.ZERO
	var left := safe_rect.position.x
	var top := safe_rect.position.y
	var right := content_size.x - safe_rect.end.x
	var bottom := content_size.y - safe_rect.end.y
	return Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_recalculate.call_deferred()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_recalculate):
		vp.size_changed.connect(_recalculate)


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_recalculate):
		vp.size_changed.disconnect(_recalculate)


## 运行中注入模拟 insets（走查 / 测试用）；传 NO_INSETS 恢复默认取值链
## （先看命令行 --sim-insets，再看系统安全区）。
func set_simulated_insets(insets: Vector4) -> void:
	_sim_insets = insets
	_recalculate()


func _recalculate() -> void:
	if not is_inside_tree():
		return
	var sim := _sim_insets
	if sim.x < 0.0:
		sim = parse_sim_insets(OS.get_cmdline_user_args())
	var insets := sim if sim.x >= 0.0 else _system_insets()
	add_theme_constant_override("margin_left", roundi(maxf(insets.x, 0.0)))
	add_theme_constant_override("margin_top", roundi(maxf(insets.y, 0.0)))
	add_theme_constant_override("margin_right", roundi(maxf(insets.z, 0.0)))
	add_theme_constant_override("margin_bottom", roundi(maxf(insets.w, 0.0)))


func _system_insets() -> Vector4:
	## 系统安全区 → canvas 坐标 insets（窗口像素 ≠ canvas 像素，换算见类注释）。
	var window := get_window()
	var viewport := get_viewport()
	if window == null or viewport == null or DisplayServer.get_name() == "headless":
		return Vector4.ZERO
	# 先与窗口矩形求交：兜底桌面端实现返回显示器坐标（含窗口外区域）的情况，
	# 交不出有效面积（零尺寸 / 无刘海 / 不支持）即视为无安全区信息，布局零变化。
	var window_rect := Rect2(Vector2.ZERO, Vector2(window.size))
	var safe := window_rect.intersection(Rect2(DisplayServer.get_display_safe_area()))
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector4.ZERO
	var to_canvas := window.get_final_transform().affine_inverse()
	var p0 := to_canvas * safe.position
	var p1 := to_canvas * safe.end
	return compute_insets(viewport.get_visible_rect().size, Rect2(p0, p1 - p0))
