class_name UpdateChecker
extends Node
## 检查更新：请求 GitHub Releases 最新发布（标题页「检查更新」入口）。
## 网络细节收敛在此；结果经 finished 信号交回 Main → EventRouter 渲染结果页。
## 页面渲染与状态改动不在这里做（保持「UI 层只读 router」的项目约定）。

signal finished(result: Dictionary)

const TIMEOUT_SEC := 10.0

var _http: HTTPRequest
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


## 发起检查；结果（成功或失败）稍后经 finished 回传一次
func check(repo: String) -> void:
	if repo == "":
		finished.emit({"ok": false, "error": "no_repo"})
		return
	if _busy:
		# 已有检查在途：保持「检查中」页面，等在途请求回包
		return
	_busy = true
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: a-word-game-update-check",
	])
	var err := _http.request("https://api.github.com/repos/%s/releases/latest" % repo, headers)
	if err != OK:
		_busy = false
		finished.emit({"ok": false, "error": "request_failed_%d" % err})


func _on_request_completed(_result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if status != 200:
		finished.emit({"ok": false, "error": "http_%d" % status})
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		finished.emit({"ok": false, "error": "bad_payload"})
		return
	var payload: Dictionary = data
	var apk_url := ""
	for asset: Variant in payload.get("assets", []):
		if typeof(asset) != TYPE_DICTIONARY:
			continue
		var asset_name := String(asset.get("name", ""))
		if asset_name.ends_with(".apk"):
			apk_url = String(asset.get("browser_download_url", ""))
			break
	finished.emit({
		"ok": true,
		"tag": String(payload.get("tag_name", "")),
		"version": String(payload.get("tag_name", "")).trim_prefix("v").trim_prefix("V"),
		"notes": String(payload.get("body", "")),
		"apk_url": apk_url,
		"html_url": String(payload.get("html_url", "")),
	})
