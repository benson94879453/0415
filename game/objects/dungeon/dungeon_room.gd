class_name DungeonRoom
extends Node2D

## 單一地牢房間節點
## 根據 room_type 和連接方向動態生成牆壁、地板、門。
## 每個房間大小固定為 ROOM_WIDTH x ROOM_HEIGHT 像素。

enum RoomType {
	START,       ## 起始房間
	MONSTER,     ## 基礎怪物房間
	ELITE,       ## 菁英怪物房間
	SHOP,        ## 商店房間
	EXIT,        ## 通往下一層的房間
}

## 四個方向
enum Dir { UP, DOWN, LEFT, RIGHT }

const ROOM_WIDTH: float = 1100.0
const ROOM_HEIGHT: float = 620.0
const WALL_THICKNESS: float = 10.0
const DOOR_WIDTH: float = 80.0
const DOOR_DETECT_DEPTH: float = 60.0  ## 門偵測區域向房間內延伸的深度

## 房間類型對應的地板顏色
const TYPE_COLORS: Dictionary = {
	RoomType.START:   Color(0.22, 0.28, 0.22, 1),  # 暗綠
	RoomType.MONSTER: Color(0.18, 0.16, 0.22, 1),  # 暗紫灰
	RoomType.ELITE:   Color(0.28, 0.14, 0.18, 1),  # 暗紅
	RoomType.SHOP:    Color(0.20, 0.22, 0.30, 1),  # 暗藍
	RoomType.EXIT:    Color(0.26, 0.24, 0.16, 1),  # 暗金
}

const TYPE_LABELS: Dictionary = {
	RoomType.START:   "起點",
	RoomType.MONSTER: "怪物",
	RoomType.ELITE:   "菁英",
	RoomType.SHOP:    "商店",
	RoomType.EXIT:    "出口",
}

## 地面物品容器設定
const GROUND_COLS := 6
const GROUND_DEFAULT_ROWS := 4
const GROUND_MAX_ROWS := 20

var room_type: RoomType = RoomType.MONSTER
var grid_pos: Vector2i = Vector2i.ZERO

## 該房間在哪些方向有門 (連接到相鄰房間)
var connections: Array[int] = []  # Dir values

## 每個方向的門 Area2D 參照
var door_areas: Dictionary = {}  # Dir -> Area2D

## 地面物品系統
var ground_container: InvContainer
var _ground_items_node: Node2D  # parent node for GroundItemVisual instances
var _player_ref: CharacterBody2D = null  # set by dungeon.gd
var _ground_visuals: Dictionary = {}  # ItemInstance → GroundItemVisual


func _ready() -> void:
	_build_room()


func _build_room() -> void:
	_create_floor()
	_create_label()
	_create_walls_and_doors()
	_init_ground_container()


func _create_floor() -> void:
	var floor_rect := ColorRect.new()
	floor_rect.name = "Floor"
	var hw := ROOM_WIDTH / 2.0
	var hh := ROOM_HEIGHT / 2.0
	floor_rect.offset_left = -hw
	floor_rect.offset_top = -hh
	floor_rect.offset_right = hw
	floor_rect.offset_bottom = hh
	floor_rect.color = TYPE_COLORS.get(room_type, Color(0.18, 0.16, 0.22, 1))
	add_child(floor_rect)


func _create_label() -> void:
	var lbl := Label.new()
	lbl.name = "RoomLabel"
	lbl.text = TYPE_LABELS.get(room_type, "???")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.offset_left = -40.0
	lbl.offset_top = -16.0
	lbl.offset_right = 40.0
	lbl.offset_bottom = 16.0
	lbl.add_theme_font_size_override("font_size", 18)
	add_child(lbl)


func _create_walls_and_doors() -> void:
	var hw := ROOM_WIDTH / 2.0
	var hh := ROOM_HEIGHT / 2.0
	var wt := WALL_THICKNESS
	var dw := DOOR_WIDTH / 2.0

	# 每面牆：如果該方向有門就分成兩段 + 一個門 Area2D，否則一整段
	# UP wall (y = -hh)
	_build_wall_side(Dir.UP, Vector2(-hw, -hh - wt), Vector2(hw, -hh), dw)
	# DOWN wall (y = hh)
	_build_wall_side(Dir.DOWN, Vector2(-hw, hh), Vector2(hw, hh + wt), dw)
	# LEFT wall (x = -hw)
	_build_wall_side(Dir.LEFT, Vector2(-hw - wt, -hh), Vector2(-hw, hh), dw)
	# RIGHT wall (x = hw)
	_build_wall_side(Dir.RIGHT, Vector2(hw, -hh), Vector2(hw + wt, hh), dw)


func _build_wall_side(dir: int, rect_min: Vector2, rect_max: Vector2, half_door: float) -> void:
	var has_door := dir in connections
	var is_horizontal := dir == Dir.UP or dir == Dir.DOWN

	if not has_door:
		# 一整段牆
		_add_wall_segment(rect_min, rect_max)
		_add_wall_visual(rect_min, rect_max)
	else:
		if is_horizontal:
			# 左段牆壁
			_add_wall_segment(rect_min, Vector2(-half_door, rect_max.y))
			_add_wall_visual(rect_min, Vector2(-half_door, rect_max.y))
			# 右段牆壁
			_add_wall_segment(Vector2(half_door, rect_min.y), rect_max)
			_add_wall_visual(Vector2(half_door, rect_min.y), rect_max)
			# 門口不可通行的透明橫牆 — 擋住缺口，只能按 E 傳送
			var block_y: float = (rect_min.y + rect_max.y) / 2.0
			_add_wall_segment(
				Vector2(-half_door, rect_min.y),
				Vector2(half_door, rect_max.y)
			)
			# 門偵測 Area2D — 完全在房間內部
			var detect_y: float
			if dir == Dir.UP:
				detect_y = rect_max.y + DOOR_DETECT_DEPTH / 2.0
			else:
				detect_y = rect_min.y - DOOR_DETECT_DEPTH / 2.0
			var door_center := Vector2(0.0, detect_y)
			_add_door(dir, door_center, Vector2(half_door * 2.0, DOOR_DETECT_DEPTH))
			# 門的視覺提示維持在牆壁位置
			_add_door_visual(Vector2(0.0, block_y), Vector2(half_door * 2.0, WALL_THICKNESS + 4.0))
		else:
			# 上段牆壁
			_add_wall_segment(rect_min, Vector2(rect_max.x, -half_door))
			_add_wall_visual(rect_min, Vector2(rect_max.x, -half_door))
			# 下段牆壁
			_add_wall_segment(Vector2(rect_min.x, half_door), rect_max)
			_add_wall_visual(Vector2(rect_min.x, half_door), rect_max)
			# 門口不可通行的透明豎牆 — 擋住缺口
			var block_x: float = (rect_min.x + rect_max.x) / 2.0
			_add_wall_segment(
				Vector2(rect_min.x, -half_door),
				Vector2(rect_max.x, half_door)
			)
			# 門偵測 Area2D — 完全在房間內部
			var detect_x: float
			if dir == Dir.LEFT:
				detect_x = rect_max.x + DOOR_DETECT_DEPTH / 2.0
			else:
				detect_x = rect_min.x - DOOR_DETECT_DEPTH / 2.0
			var door_center := Vector2(detect_x, 0.0)
			_add_door(dir, door_center, Vector2(DOOR_DETECT_DEPTH, half_door * 2.0))
			# 門的視覺提示維持在牆壁位置
			_add_door_visual(Vector2(block_x, 0.0), Vector2(WALL_THICKNESS + 4.0, half_door * 2.0))


func _add_wall_segment(rect_min: Vector2, rect_max: Vector2) -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	var size := rect_max - rect_min
	rect_shape.size = size.abs()
	shape.shape = rect_shape
	shape.position = (rect_min + rect_max) / 2.0
	body.add_child(shape)
	add_child(body)


func _add_wall_visual(rect_min: Vector2, rect_max: Vector2) -> void:
	var visual := ColorRect.new()
	visual.offset_left = rect_min.x
	visual.offset_top = rect_min.y
	visual.offset_right = rect_max.x
	visual.offset_bottom = rect_max.y
	visual.color = Color(0.4, 0.35, 0.45, 1)
	add_child(visual)


func _add_door(dir: int, center: Vector2, size: Vector2) -> void:
	var area := Area2D.new()
	area.name = "Door_%d" % dir
	area.position = center
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true

	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = size
	shape.shape = rect_shape
	area.add_child(shape)

	add_child(area)
	door_areas[dir] = area


func _add_door_visual(center: Vector2, size: Vector2) -> void:
	var visual := ColorRect.new()
	visual.offset_left = center.x - size.x / 2.0
	visual.offset_top = center.y - size.y / 2.0
	visual.offset_right = center.x + size.x / 2.0
	visual.offset_bottom = center.y + size.y / 2.0
	visual.color = Color(0.5, 0.4, 0.3, 0.6)
	add_child(visual)


## 設定玩家參照（由 dungeon.gd 呼叫）
func set_player(p: CharacterBody2D) -> void:
	_player_ref = p
	for visual in _ground_visuals.values():
		if not is_instance_valid(visual):
			continue
		if not visual.body_entered.is_connected(_on_ground_body_entered.bind(visual)):
			visual.body_entered.connect(_on_ground_body_entered.bind(visual))
		if not visual.body_exited.is_connected(_on_ground_body_exited.bind(visual)):
			visual.body_exited.connect(_on_ground_body_exited.bind(visual))


## 初始化地面物品容器與視覺節點
func _init_ground_container() -> void:
	ground_container = InvContainer.new(GROUND_COLS, GROUND_DEFAULT_ROWS)
	ground_container.contents_changed.connect(_on_ground_contents_changed)
	_ground_items_node = Node2D.new()
	_ground_items_node.name = "GroundItems"
	add_child(_ground_items_node)


## 新增地面物品；自動擴展容器直到 GROUND_MAX_ROWS
func add_ground_item(item: ItemInstance, world_pos: Vector2) -> bool:
	item.metadata["drop_pos_x"] = world_pos.x
	item.metadata["drop_pos_y"] = world_pos.y
	if ground_container.add_item(item) >= 0:
		return true
	# 自動擴充列數
	while ground_container.height < GROUND_MAX_ROWS:
		ground_container.resize(GROUND_COLS, ground_container.height + 2)
		if ground_container.add_item(item) >= 0:
			return true
	return false


## 容器內容變動時同步視覺節點
func _on_ground_contents_changed() -> void:
	var current_items: Array = ground_container.get_all_items()
	var current_set: Dictionary = {}
	for it in current_items:
		current_set[it] = true

	# 移除已不在容器中的視覺
	for it in _ground_visuals.keys():
		if not current_set.has(it):
			var old_vis: GroundItemVisual = _ground_visuals[it]
			if is_instance_valid(old_vis):
				if is_instance_valid(_player_ref):
					_player_ref.unregister_interactable(old_vis)
				old_vis.queue_free()
			_ground_visuals.erase(it)

	# 為新物品建立視覺
	for it in current_items:
		if _ground_visuals.has(it):
			continue
		# 計算掉落位置
		var world_pos := _get_drop_position(it)
		var visual := GroundItemVisual.create(it, self, world_pos)
		# 綁定玩家互動
		if is_instance_valid(_player_ref):
			visual.body_entered.connect(_on_ground_body_entered.bind(visual))
			visual.body_exited.connect(_on_ground_body_exited.bind(visual))
		_ground_items_node.add_child(visual)
		_ground_visuals[it] = visual


func _on_ground_body_entered(body: Node2D, visual: GroundItemVisual) -> void:
	if body == _player_ref:
		_player_ref.register_interactable(visual)


func _on_ground_body_exited(body: Node2D, visual: GroundItemVisual) -> void:
	if body == _player_ref:
		_player_ref.unregister_interactable(visual)


## 從 item.metadata 取得掉落位置，缺少則隨機生成（避開重疊）
func _get_drop_position(item: ItemInstance) -> Vector2:
	if item.metadata.has("drop_pos_x") and item.metadata.has("drop_pos_y"):
		return Vector2(item.metadata["drop_pos_x"], item.metadata["drop_pos_y"])
	# 房間安全區域 70%
	var safe_w := ROOM_WIDTH * 0.35
	var safe_h := ROOM_HEIGHT * 0.35
	for _attempt in range(10):
		var offset := Vector2(randf_range(-safe_w, safe_w), randf_range(-safe_h, safe_h))
		var candidate := offset
		var too_close := false
		for vis in _ground_visuals.values():
			if not is_instance_valid(vis):
				continue
			if candidate.distance_to(vis.position) < 30.0:
				too_close = true
				break
		if not too_close:
			return candidate
	# 10 次都失敗就直接回傳隨機位置
	return Vector2(randf_range(-safe_w, safe_w), randf_range(-safe_h, safe_h))


## 序列化地面物品（存檔用）
func serialize_ground() -> Dictionary:
	return {
		"container": ground_container.serialize(),
	}


## 反序列化地面物品（讀檔用）
func deserialize_ground(data: Dictionary) -> void:
	if data.has("container"):
		ground_container.deserialize(data["container"])


## 取得房間在世界空間中的中心位置 (根據 grid_pos)
static func grid_to_world(gpos: Vector2i) -> Vector2:
	# 間距要夠大，確保 camera 只看到當前房間
	return Vector2(
		gpos.x * (ROOM_WIDTH + 800.0),
		gpos.y * (ROOM_HEIGHT + 800.0),
	)
