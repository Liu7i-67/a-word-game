extends Control
## 主场景入口：装配 PlayerState / EventRouter / 界面屏，
## 管理「标题→游戏」切换与生命周期存档（Android 暂停 / 桌面关闭）。

var router: EventRouter
var title_screen: TitleScreen
var game_screen: GameScreen
var _tour: RefCounted = null


func _ready() -> void:
	GameData.ensure_loaded()
	theme = _make_theme()
	router = EventRouter.new()
	router.setup(PlayerState, EventBus)
	router.game_started.connect(_on_game_started)
	router.continue_requested.connect(_on_continue)
	_show_title()
	if OS.get_cmdline_user_args().has("--shot-tour"):
		print("TOUR: 进入走查模式")
		var tour_script: GDScript = load("res://scripts/dev/shot_tour.gd")
		print("TOUR: 脚本加载 ", "成功" if tour_script != null else "失败")
		if tour_script != null:
			_tour = tour_script.new()
			_tour.call_deferred("run", self)


func _show_title() -> void:
	GameManager.enter_state(GameManager.State.TITLE)
	title_screen = TitleScreen.new(router)
	add_child(title_screen)


func _on_game_started() -> void:
	_start_game()


func _on_continue() -> void:
	SaveManager.load_game()
	if not PlayerState.read_from(SaveManager.data):
		push_error("Main: 存档读取失败，留在标题页")
		return
	_start_game()


func _start_game() -> void:
	GameManager.enter_state(GameManager.State.PLAYING)
	if title_screen != null:
		title_screen.queue_free()
		title_screen = null
	game_screen = GameScreen.new(router, PlayerState)
	add_child(game_screen)
	PlayerState.write_to(SaveManager.data)
	SaveManager.save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_if_playing()


func _save_if_playing() -> void:
	if GameManager.state == GameManager.State.PLAYING and PlayerState.nickname != "":
		PlayerState.write_to(SaveManager.data)
		SaveManager.save_game()


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 26
	return th
