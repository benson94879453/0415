extends Node2D

## 地牢場景
## 使用 DungeonGenerator 隨機生成房間佈局。
## Camera 固定在目前房間中心，不跟隨玩家。
## 只顯示當前房間，其他房間隱藏。
## 房間轉場使用 SceneTransition.fade_only()，沿用同一個 Player 實例。

@onready var camera: Camera2D = %Camera
@onready var player: CharacterBody2D = %Player
@onready var rooms_container: Node2D = %Rooms

var _room_nodes: Dictionary = {}  # Vector2i → DungeonRoom
var _current_grid_pos: Vector2i = Vector2i.ZERO
var _map: DungeonMap
var _player_inventory: PlayerInventory
var _inventory_ui: InventoryUI


func _ready() -> void:
	_generate_dungeon()
	_place_player_in_start()
	player.interacted.connect(_on_player_interacted)
	# 延遲一幀確保所有房間的 _ready 完成後再設定可見性
	_show_only_current_room.call_deferred()


func _generate_dungeon() -> void:
	var generator := DungeonGenerator.new()
	var room_datas: Array[DungeonGenerator.RoomData] = generator.generate()

	for data in room_datas:
		var room := DungeonRoom.new()
		room.room_type = data.room_type
		room.grid_pos = data.grid_pos
		room.connections = data.connections
		room.position = DungeonRoom.grid_to_world(data.grid_pos)
		rooms_container.add_child(room)
		_room_nodes[data.grid_pos] = room

		# add_child 已同步觸發 room._ready()，門已建立，直接綁定
		_bind_room_doors(room)

	# 建立地圖系統
	_map = DungeonMap.new()
	add_child(_map)
	_map.setup(generator.rooms, generator.room_map, Vector2i.ZERO)

	# 建立背包系統
	_player_inventory = PlayerInventory.new()
	_inventory_ui = InventoryUI.new()
	add_child(_inventory_ui)
	_inventory_ui.setup(_player_inventory)

	# 測試用：放入一些初始物品
	_player_inventory.add_item(ItemInstance.new("wooden_sword"))
	_player_inventory.add_item(ItemInstance.new("iron_shield"))
	_player_inventory.add_item(ItemInstance.new("health_potion"))
	_player_inventory.add_item(ItemInstance.new("health_potion"))
	_player_inventory.add_item(ItemInstance.new("swift_boots"))
	_player_inventory.add_item(ItemInstance.new("dragon_set_helm"))
	_player_inventory.add_item(ItemInstance.new("dragon_set_armor"))


func _bind_room_doors(room: DungeonRoom) -> void:
	for dir in room.door_areas:
		var area: Area2D = room.door_areas[dir]
		area.body_entered.connect(func(body: Node2D) -> void:
			if body == player:
				player.register_interactable(area)
		)
		area.body_exited.connect(func(body: Node2D) -> void:
			if body == player:
				player.unregister_interactable(area)
		)


func _on_player_interacted(target: Area2D) -> void:
	if SceneTransition.is_transitioning():
		return
	# 找到目標門所屬的房間和方向
	for grid_pos in _room_nodes:
		var room: DungeonRoom = _room_nodes[grid_pos]
		for dir in room.door_areas:
			if room.door_areas[dir] == target:
				_move_to_adjacent_room(grid_pos, dir)
				return


func _move_to_adjacent_room(from_pos: Vector2i, dir: int) -> void:
	var offset: Vector2i = DungeonGenerator.DIRS[dir]
	var to_pos: Vector2i = from_pos + offset
	if to_pos not in _room_nodes:
		return

	# 使用 fade 轉場，在全黑時搬移玩家和切換可見房間
	SceneTransition.fade_only(_do_room_switch.bind(to_pos, dir), 0.3)


func _do_room_switch(to_pos: Vector2i, dir: int) -> void:
	_current_grid_pos = to_pos

	# 更新地圖：標記已探索並更新當前位置
	_map.mark_explored(to_pos)
	_map.update_current_pos(to_pos)

	# 清除玩家的互動清單
	player._nearby_interactables.clear()

	# 計算玩家在新房間的入口位置
	var room_center: Vector2 = DungeonRoom.grid_to_world(to_pos)
	var enter_dir: int = DungeonGenerator.OPPOSITE_DIR[dir] as int
	var entry_offset: Vector2 = _get_entry_offset(enter_dir)
	player.global_position = room_center + entry_offset

	# Camera 切到新房間
	camera.position = room_center

	# 只顯示當前房間
	_show_only_current_room()

	# 如果是出口房間
	var target_room: DungeonRoom = _room_nodes[to_pos]
	if target_room.room_type == DungeonRoom.RoomType.EXIT:
		print("[Dungeon] 到達出口房間！")
		# TODO: 進入下一層或回到家園


## 只顯示當前房間，隱藏所有其他房間
## 不能用 visible=false（會停用物理），改用 process_mode + modulate
func _show_only_current_room() -> void:
	for grid_pos in _room_nodes:
		var room: DungeonRoom = _room_nodes[grid_pos]
		var is_current: bool = (grid_pos == _current_grid_pos)
		room.visible = is_current
		if is_current:
			room.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			room.process_mode = Node.PROCESS_MODE_DISABLED


func _get_entry_offset(from_dir: int) -> Vector2:
	var hw: float = DungeonRoom.ROOM_WIDTH / 2.0 - 50.0
	var hh: float = DungeonRoom.ROOM_HEIGHT / 2.0 - 50.0
	match from_dir:
		DungeonGenerator.DIR_UP:
			return Vector2(0, -hh)
		DungeonGenerator.DIR_DOWN:
			return Vector2(0, hh)
		DungeonGenerator.DIR_LEFT:
			return Vector2(-hw, 0)
		DungeonGenerator.DIR_RIGHT:
			return Vector2(hw, 0)
	return Vector2.ZERO


func _place_player_in_start() -> void:
	_current_grid_pos = Vector2i.ZERO
	var start_world: Vector2 = DungeonRoom.grid_to_world(Vector2i.ZERO)
	player.global_position = start_world
	camera.position = start_world
