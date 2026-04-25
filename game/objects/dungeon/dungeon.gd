extends Node2D

## 地牢場景
## 使用 DungeonGenerator 動態建立房間：初始化時只有 START，
## 隨玩家向北推進逐一建立新房間（Task 3 負責）。
## Camera 固定在目前房間中心，不跟隨玩家。
## 只顯示當前房間，其他房間隱藏。
## 房間轉場使用 SceneTransition.fade_only()，沿用同一個 Player 實例。

@onready var camera: Camera2D = %Camera
@onready var player: CharacterBody2D = %Player
@onready var rooms_container: Node2D = %Rooms

var _room_nodes: Dictionary = {}  # Vector2i → DungeonRoom
var _current_grid_pos: Vector2i = Vector2i.ZERO
var _generator: DungeonGenerator
var _map: DungeonMap
var _player_inventory: PlayerInventory
var _inventory_ui: InventoryUI
var _ground_ui: GroundContainerUI
var _combat_player: CombatPlayer
var _selected_slot_index: int = -1  # Track which north slot is selected
var _slot_targets: Array[Area2D] = []  # Cached list of visible Door/WallSlot in current room


func _ready() -> void:
	_init_dungeon()
	_on_enter_room(_room_nodes[Vector2i.ZERO])
	player.interacted.connect(_on_player_interacted)
	# 延遲一幀確保所有房間的 _ready 完成後再設定可見性
	_show_only_current_room.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	# Tab key: cycle through visible slots
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_cycle_slot_selection()
		get_viewport().set_input_as_handled()
	# E key (interact action): apply blueprint to selected slot
	elif event.is_action_pressed("interact") and _selected_slot_index >= 0:
		_apply_blueprint_to_selected_slot()
		get_viewport().set_input_as_handled()


## 初始化地牢：建立生成器，只建立 START 房間
func _init_dungeon() -> void:
	_generator = DungeonGenerator.new()
	var start_data: DungeonGenerator.RoomData = _generator.init_run()
	_create_room_node(start_data)

	# 建立地圖系統
	_map = DungeonMap.new()
	add_child(_map)
	_map.setup(_generator.rooms, _generator.room_map, Vector2i.ZERO)

	# 建立背包系統
	_player_inventory = PlayerInventory.new()
	_inventory_ui = InventoryUI.new()
	add_child(_inventory_ui)
	_inventory_ui.setup(_player_inventory)
	_inventory_ui.item_dropped_from_inventory.connect(_on_inventory_item_dropped)
	_inventory_ui.blueprint_applied_to_slot.connect(_on_blueprint_applied_to_slot)

	_ground_ui = GroundContainerUI.new()
	add_child(_ground_ui)

	# 初始化背包數值評估器
	InventoryEvaluator.setup(_player_inventory)

	# 初始物品：基礎戰鬥物品 + 2 個隨機藍圖
	_player_inventory.add_item(ItemInstance.new("wooden_sword"))
	_player_inventory.add_item(ItemInstance.new("health_potion"))
	_player_inventory.add_item(ItemInstance.new("health_potion"))
	_player_inventory.add_item(ItemInstance.new(_random_blueprint_id()))
	_player_inventory.add_item(ItemInstance.new(_random_blueprint_id()))


## 根據 RoomData 建立 DungeonRoom 節點
func _create_room_node(data: DungeonGenerator.RoomData) -> DungeonRoom:
	var room := DungeonRoom.new()
	room.room_type = data.room_type
	room.grid_pos = data.grid_pos
	room.connections = data.connections
	room.position = DungeonRoom.grid_to_world(data.grid_pos)
	rooms_container.add_child(room)
	room.set_player(player)
	room.room_cleared.connect(_on_room_cleared)
	_bind_room_doors(room)
	_room_nodes[data.grid_pos] = room
	return room


## 為房間生成敵人（MONSTER / ELITE 房間才生成）
func _spawn_enemies_for_room(room: DungeonRoom) -> void:
	if room.room_type != DungeonRoom.RoomType.MONSTER and room.room_type != DungeonRoom.RoomType.ELITE:
		return
	var count := 3 if room.room_type == DungeonRoom.RoomType.ELITE else 2
	var room_center: Vector2 = DungeonRoom.grid_to_world(room.grid_pos)
	for i in count:
		var enemy := EnemyBase.new()
		enemy.max_hp = 50.0 if room.room_type == DungeonRoom.RoomType.ELITE else 30.0
		enemy.move_speed = 100.0 if room.room_type == DungeonRoom.RoomType.ELITE else 80.0
		enemy.contact_damage = 8.0 if room.room_type == DungeonRoom.RoomType.ELITE else 5.0
		var angle := (i as float) * TAU / count
		enemy.global_position = room_center + Vector2(cos(angle), sin(angle)) * 150.0
		rooms_container.add_child(enemy)
		enemy.setup(player)


func _bind_room_doors(room: DungeonRoom) -> void:
	for dir in room.door_areas:
		_bind_door_signals(room.door_areas[dir])


func _bind_door_signals(area: Area2D) -> void:
	area.body_entered.connect(func(body: Node2D) -> void:
		if body == player:
			player.register_interactable(area)
	)
	area.body_exited.connect(func(body: Node2D) -> void:
		if body == player:
			player.unregister_interactable(area)
	)


## 進入房間：更新位置、地圖、移動玩家和相機、顯示當前房間
func _on_enter_room(room: DungeonRoom) -> void:
	# Reset slot selection when entering new room
	_selected_slot_index = -1
	_slot_targets.clear()

	_current_grid_pos = room.grid_pos

	# 更新地圖
	_map.mark_explored(room.grid_pos)
	_map.update_current_pos(room.grid_pos)

	# 清除玩家的互動清單
	player._nearby_interactables.clear()

	# 預設放在房間中心（透過門進入時會由 _do_room_switch 覆蓋）
	player.global_position = DungeonRoom.grid_to_world(room.grid_pos)

	# Camera 切到新房間
	camera.position = DungeonRoom.grid_to_world(room.grid_pos)

	# 只顯示當前房間
	_show_only_current_room()

	# Update inventory UI with current room's slot data
	if _inventory_ui != null:
		if room.has_method("get_north_slots_info"):
			_inventory_ui.set_dungeon_slots(room.get_north_slots_info())
		else:
			_inventory_ui.set_dungeon_slots([])

	# 為有敵人的房間生成怪物
	_spawn_enemies_for_room(room)

	# 如果是出口房間
	if room.room_type == DungeonRoom.RoomType.EXIT:
		print("[Dungeon] Run complete!")
		SceneTransition.fade_only(func() -> void:
			get_tree().change_scene_to_file("res://game/objects/homestead/homestead.tscn")
		, 0.3)


func _on_player_interacted(target: Area2D) -> void:
	if SceneTransition.is_transitioning():
		return
	if target is GroundItemVisual:
		_open_ground_container(target)
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
	if _ground_ui != null:
		_ground_ui.close()

	# 使用 fade 轉場，在全黑時搬移玩家和切換可見房間
	SceneTransition.fade_only(_do_room_switch.bind(to_pos, dir), 0.3)


func _do_room_switch(to_pos: Vector2i, dir: int) -> void:
	# 進入新房間
	var target_room: DungeonRoom = _room_nodes[to_pos]
	_on_enter_room(target_room)

	# 計算從反方向進入的偏移
	var enter_dir: int = DungeonGenerator.OPPOSITE_DIR[dir] as int
	var entry_offset: Vector2 = _get_entry_offset(enter_dir)
	player.global_position = DungeonRoom.grid_to_world(to_pos) + entry_offset


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


func _get_current_room() -> DungeonRoom:
	return _room_nodes.get(_current_grid_pos, null)


func _open_ground_container(target: GroundItemVisual) -> void:
	if target == null or target.room_ref == null:
		return
	var room = target.room_ref
	if room != _get_current_room():
		return
	if _inventory_ui != null and _inventory_ui._is_open:
		_inventory_ui.toggle()
	_ground_ui.setup(room.ground_container, _player_inventory, player, target.global_position, room)
	_ground_ui.open()


func _on_inventory_item_dropped(item: ItemInstance) -> void:
	var room := _get_current_room()
	if room == null:
		_player_inventory.add_item(item)
		return
	var local_drop_pos := room.to_local(player.global_position)
	if not room.add_ground_item(item, local_drop_pos):
		_player_inventory.add_item(item)


func _on_blueprint_applied_to_slot(item: ItemInstance, slot_index: int) -> void:
	var room := _get_current_room()
	if room == null:
		_player_inventory.add_item(item)
		return
	# Find the Door/WallSlot with matching slot_index
	var target_slot: Area2D = null
	for slot in room.north_slots:
		if slot is Door or slot is WallSlot:
			if slot.slot_index == slot_index:
				target_slot = slot
				break
	if target_slot == null:
		print("[Dungeon] Slot index %d not found" % slot_index)
		_player_inventory.add_item(item)
		return
	_apply_blueprint_to_slot(item, target_slot)


func _apply_blueprint_to_slot(item: ItemInstance, slot_node: Area2D) -> void:
	var current_room := _get_current_room()
	if current_room == null:
		_player_inventory.add_item(item)
		return

	# ── 解析藍圖 room_type ──
	var blueprint_data: Dictionary = item.get_definition().get("blueprint", {})
	var room_type_str: String = blueprint_data.get("room_type", "")
	if room_type_str.is_empty():
		print("[Dungeon] Invalid blueprint: no room_type")
		_player_inventory.add_item(item)
		return

	var room_type_keys: Array = DungeonRoom.RoomType.keys()
	var type_index: int = room_type_keys.find(room_type_str)
	if type_index < 0:
		print("[Dungeon] Unknown room_type: %s" % room_type_str)
		_player_inventory.add_item(item)
		return
	var new_room_type: int = type_index

	var target_pos: Vector2i = slot_node.target_grid_pos
	var is_door: bool = not slot_node.is_blank  # Door = not blank

	# ── Door 插槽：如果房間已存在，更換類型 ──
	if is_door and target_pos in _room_nodes:
		var existing_room: DungeonRoom = _room_nodes[target_pos]
		existing_room.update_room_type(new_room_type)
		print("[Dungeon] Changed room at %s to %s via blueprint %s" % [
			target_pos,
			DungeonRoom.RoomType.keys()[new_room_type],
			item.item_id,
		])
		# 藍圖消耗（不返還背包）
		# 移除已使用的 slot 並刷新 UI
		current_room.remove_north_slot(slot_node.slot_index)
		if _inventory_ui != null:
			_inventory_ui.set_dungeon_slots(current_room.get_north_slots_info())
		return

	# ── 檢查目標位置是否已有房間（WallSlot 或新建情況） ──
	if target_pos in _room_nodes:
		print("[Dungeon] Room already exists at %s, cannot place blueprint" % target_pos)
		_player_inventory.add_item(item)
		return

	# ── 透過生成器建立新房間 ──
	var new_data: DungeonGenerator.RoomData = _generator.create_north_room(
		current_room.grid_pos, new_room_type
	)
	if new_data == null:
		print("[Dungeon] Generator rejected room creation at %s" % target_pos)
		_player_inventory.add_item(item)
		return

	# ── 建立房間節點 ──
	var new_room := _create_room_node(new_data)

	# ── 為當前房間新增北方門（讓玩家可以走過去） ──
	current_room.add_connection_door(DungeonRoom.Dir.UP)
	# 綁定新門的互動信號
	if DungeonRoom.Dir.UP in current_room.door_areas:
		_bind_door_signals(current_room.door_areas[DungeonRoom.Dir.UP])

	# ── 移除已使用的北牆插槽 ──
	current_room.remove_north_slot(slot_node.slot_index)

	# Refresh slot data in inventory UI (slots may be hidden now)
	if _inventory_ui != null:
		_inventory_ui.set_dungeon_slots(current_room.get_north_slots_info())

	# ── 更新地圖 ──
	_map.setup(_generator.rooms, _generator.room_map, Vector2i.ZERO)

	print("[Dungeon] Created %s room at %s via blueprint %s" % [
		DungeonRoom.RoomType.keys()[new_room_type],
		target_pos,
		item.item_id,
	])
	# 藍圖消耗 — 不返還背包


## 獲取隨機藍圖 ID（獎勵池）
func _random_blueprint_id() -> String:
	var pool = ["bp_monster_room", "bp_elite_room", "bp_shop_room"]
	return pool[randi() % pool.size()]


## 處理房間清除事件：為 MONSTER / ELITE 房間首次清除時發放藍圖獎勵
func _on_room_cleared(room: DungeonRoom) -> void:
	# 防止重複發放獎勵
	if room.reward_granted:
		return
	# 只對 MONSTER 和 ELITE 房間發放獎勵
	if room.room_type != DungeonRoom.RoomType.MONSTER and room.room_type != DungeonRoom.RoomType.ELITE:
		return
	# 標記獎勵已發放
	room.reward_granted = true
	# 發放隨機藍圖
	var blueprint_id = _random_blueprint_id()
	var blueprint_item = ItemInstance.new(blueprint_id)
	_player_inventory.add_item(blueprint_item)
	print("[Dungeon] Blueprint reward: %s granted for clearing room" % blueprint_id)


## Cycle through visible Door/WallSlot nodes with Tab key
func _cycle_slot_selection() -> void:
	var current_room := _get_current_room()
	if current_room == null:
		return

	# Build fresh list of visible Door/WallSlot nodes from north_slots
	_slot_targets.clear()
	if current_room.has_method("get_north_slots"):
		for slot in current_room.get_north_slots():
			if slot is Door or slot is WallSlot:
				# Check if the slot is visible (parent node visible)
				if slot.get_parent() != null and slot.get_parent().visible:
					_slot_targets.append(slot)

	# If no visible slots, clear selection and return
	if _slot_targets.is_empty():
		if _selected_slot_index >= 0:
			# Clear previous highlight if any
			_set_slot_highlight(_selected_slot_index, false)
			_selected_slot_index = -1
		print("[Dungeon] No visible slots to select")
		return

	# Cycle to next slot (wrap around)
	var old_index := _selected_slot_index
	_selected_slot_index = (_selected_slot_index + 1) % _slot_targets.size()

	# Update highlights
	if old_index >= 0 and old_index < _slot_targets.size():
		_set_slot_highlight(old_index, false)
	_set_slot_highlight(_selected_slot_index, true)

	print("[Dungeon] Selected slot %d of %d" % [_selected_slot_index, _slot_targets.size()])


## Apply blueprint to the currently selected slot (E key)
func _apply_blueprint_to_selected_slot() -> void:
	if _selected_slot_index < 0 or _selected_slot_index >= _slot_targets.size():
		return

	var current_room := _get_current_room()
	if current_room == null:
		return

	# Find first blueprint in inventory
	var blueprint_item: ItemInstance = null
	for item in _player_inventory.get_all_items():
		var definition = item.get_definition()
		if definition.has("item_category") and definition["item_category"] == "blueprint":
			blueprint_item = item
			break

	if blueprint_item == null:
		print("[Dungeon] No blueprint in inventory")
		return

	# Remove blueprint from inventory
	_player_inventory.remove_item(blueprint_item)

	# Apply blueprint to selected slot
	var selected_slot = _slot_targets[_selected_slot_index]
	_apply_blueprint_to_slot(blueprint_item, selected_slot)

	# Reset selection after applying
	_selected_slot_index = -1


## Set highlight on a slot by index
func _set_slot_highlight(index: int, enabled: bool) -> void:
	if index < 0 or index >= _slot_targets.size():
		return
	var slot = _slot_targets[index]
	if slot.has_method("set_highlight"):
		slot.set_highlight(enabled)
