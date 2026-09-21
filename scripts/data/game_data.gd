class_name GameData
## 静态数据入口：加载并查询 data/ 下 JSON（配置/剧情/物品/怪物/场景）。
## 纯数据容器，按 Autoload 边界规范不做成 Autoload；使用前先 ensure_loaded()。

static var config: Dictionary = {}
static var story: Dictionary = {}
static var items: Dictionary = {}
static var monsters: Dictionary = {}
static var scenes_by_id: Dictionary = {}
static var scene_order: PackedStringArray = []
static var ports: PackedStringArray = []
static var regions: PackedStringArray = []
static var active_region: String = ""
static var city_map_name: String = "城内地图"
## 大世界港口（契约 docs/trade-spec.md §2，data/world.json）：[{id,name,region,scene,specialties,demand_pool}]
## 属增量数据：world.json 缺失时保持空数组，各系统自行兜底。
static var world_ports: Array[Dictionary] = []
## 区域世界（契约 docs/sail-region-spec.md §1.8，world.json regions 原样加载）：
## [{id,name,map_kind,map_name,port_scene,desc,scenes}]；属增量数据：world.json
## 未含 regions 时保持空数组，region_of_scene 返回 {} 由调用方兜底。
static var regions_data: Array[Dictionary] = []

const _DATA_DIR := "res://data/"


static func load_all() -> void:
	config = _read_json("config.json")
	story = _read_json("story.json")
	items = _read_json("items.json").get("items", {})
	monsters = _read_json("monsters.json").get("monsters", {})
	var scenes_doc := _read_json("scenes.json")
	var world_doc := _read_json_optional("world.json")
	world_ports = []
	for entry in world_doc.get("ports", []):
		if entry is Dictionary:
			world_ports.append(entry)
	# 契约 sail-region §1.8：区域表与 ports 平级，原样加载（缺失保持空数组）
	regions_data = []
	for entry in world_doc.get("regions", []):
		if entry is Dictionary:
			regions_data.append(entry)
	ports = PackedStringArray(scenes_doc.get("ports", []))
	if ports.is_empty() and not world_ports.is_empty():
		# scenes.json 未再提供港口名清单时，从 world.json 推导，保持旧接口可用
		var names := PackedStringArray()
		for p: Dictionary in world_ports:
			names.append(String(p.get("name", p.get("id", ""))))
		ports = names
	regions = PackedStringArray(scenes_doc.get("regions", []))
	active_region = String(scenes_doc.get("active_region", ""))
	city_map_name = String(scenes_doc.get("city_map_name", "城内地图"))
	scenes_by_id = {}
	scene_order = PackedStringArray()
	for scene: Dictionary in scenes_doc.get("scenes", []):
		var id := String(scene.get("id", ""))
		if id == "":
			push_error("GameData: 存在缺少 id 的场景")
			continue
		if scenes_by_id.has(id):
			push_error("GameData: 场景 id 重复 %s" % id)
			continue
		scenes_by_id[id] = scene
		scene_order.append(id)


static func ensure_loaded() -> void:
	if scenes_by_id.is_empty():
		load_all()


static func get_scene(id: String) -> Dictionary:
	ensure_loaded()
	return scenes_by_id.get(id, {})


static func has_scene(id: String) -> bool:
	return not get_scene(id).is_empty()


static func get_item(id: String) -> Dictionary:
	ensure_loaded()
	return items.get(id, {})


static func has_item(id: String) -> bool:
	return not get_item(id).is_empty()


static func get_monster(id: String) -> Dictionary:
	ensure_loaded()
	return monsters.get(id, {})


static func has_monster(id: String) -> bool:
	return not get_monster(id).is_empty()


## 城内地图可跳转的场景（保持数据文件顺序）
static func map_scenes() -> Array:
	ensure_loaded()
	var result: Array = []
	for id in scene_order:
		var scene: Dictionary = scenes_by_id[id]
		if bool(scene.get("on_map", false)):
			result.append(scene)
	return result


## 区域判定（契约 docs/sail-region-spec.md §1.8）：场景命中某区的 port_scene 或
## scenes 成员即返回该区；都未命中兜底返回 venice 区（map_kind=="venice" 的项，
## 缺该项时退回 regions_data[0]）；regions 未载（空数组）返回 {}。
static func region_of_scene(scene_id: String) -> Dictionary:
	ensure_loaded()
	var fallback: Dictionary = {}
	for region: Dictionary in regions_data:
		if String(region.get("port_scene", "")) == scene_id \
				or (region.get("scenes", []) as Array).has(scene_id):
			return region
		if fallback.is_empty() and String(region.get("map_kind", "")) == "venice":
			fallback = region
	if fallback.is_empty() and not regions_data.is_empty():
		fallback = regions_data[0]
	return fallback


static func _read_json(file_name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(_DATA_DIR + file_name)
	if text.is_empty():
		push_error("GameData: 读取失败 %s (%s)" % [file_name, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("GameData: JSON 结构非法 %s" % file_name)
	return {}


## 增量数据读取（world.json 等）：并行写入/尚未落盘时静默返回空，不刷错误
static func _read_json_optional(file_name: String) -> Dictionary:
	if not FileAccess.file_exists(_DATA_DIR + file_name):
		return {}
	return _read_json(file_name)
