extends Node
## 本地加密存档（Autoload: SaveManager）。
## 适度防篡改：加密 + 内容校验和 + .bak 回退。
## 密钥仅防随手改档，可被逆向；严格校验属联机版服务端职责。

signal save_completed
signal load_completed

const SAVE_PATH := "user://save.bin"
const BACKUP_PATH := "user://save.bak"
const FORMAT_VERSION := 1
const SAVE_PASS := "a-word-game::v1::local-only"

var data: Dictionary = {}


func _ready() -> void:
	data = {"_version": FORMAT_VERSION}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(BACKUP_PATH)


func save_game() -> void:
	data["_version"] = FORMAT_VERSION
	data["_saved_at_unix"] = int(Time.get_unix_time_from_system())
	if FileAccess.file_exists(SAVE_PATH):
		if DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH) != OK:
			push_warning("SaveManager: 备份旧存档失败，继续覆盖写入")
	var payload := {"checksum": data.hash(), "data": data}
	var file := FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.WRITE, SAVE_PASS)
	if file == null:
		push_error("SaveManager: 存档写入失败 (%s)" % FileAccess.get_open_error())
		return
	file.store_var(payload, false)
	file.close()
	save_completed.emit()


func load_game() -> void:
	var payload := _read_payload(SAVE_PATH)
	if payload.is_empty() and FileAccess.file_exists(BACKUP_PATH):
		push_warning("SaveManager: 主存档不可用，回退 .bak")
		payload = _read_payload(BACKUP_PATH)
	if payload.is_empty():
		push_warning("SaveManager: 无可用存档，使用初始数据")
		data = {"_version": FORMAT_VERSION}
	else:
		var loaded: Dictionary = payload.get("data", {})
		if payload.get("checksum") != loaded.hash():
			push_error("SaveManager: 校验和不匹配，存档可能被篡改")
		data = _migrate(loaded)
	load_completed.emit()


func delete_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	DirAccess.remove_absolute(BACKUP_PATH)
	data = {"_version": FORMAT_VERSION}


func _read_payload(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, SAVE_PASS)
	if file == null:
		push_error("SaveManager: 打开存档失败 (%s) %s" % [path, FileAccess.get_open_error()])
		return {}
	var payload: Variant = file.get_var(false)
	file.close()
	if payload is Dictionary and payload.has("data"):
		return payload
	push_error("SaveManager: 存档结构非法")
	return {}


func _migrate(loaded: Dictionary) -> Dictionary:
	var save_version: int = loaded.get("_version", 0)
	if save_version > FORMAT_VERSION:
		push_error("SaveManager: 存档版本 %d 高于当前 %d" % [save_version, FORMAT_VERSION])
		return loaded
	# 版本链：逐级补字段/改默认值，如
	# if save_version < 2: loaded["new_field"] = default
	if save_version < FORMAT_VERSION:
		loaded["_version"] = FORMAT_VERSION
	return loaded
