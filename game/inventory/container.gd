class_name InvContainer
extends RefCounted

## Multi-cell item container with shape-based placement and 4-direction rotation.
## Each grid cell references the ItemInstance occupying it (or null).
## Items track their center_slot; occupied cells are derived from shape + orientation.

signal contents_changed

var width: int = 1
var height: int = 1


## 格子索引 → 行號
func _row(idx: int) -> int:
	return floori(idx / float(width))


## 格子索引 → 列號
func _col(idx: int) -> int:
	return idx % width

## _grid[slot_index] = reference to ItemInstance occupying that cell, or null
var _grid: Array = []

## All items currently in this container (unique references, no duplicates)
var _items: Array[ItemInstance] = []


func _init(p_width: int = 1, p_height: int = 1) -> void:
	width = p_width
	height = p_height
	_grid.clear()
	_grid.resize(width * height)
	for i in _grid.size():
		_grid[i] = null
	_items.clear()


func get_slot_count() -> int:
	return width * height


func pos_to_index(x: int, y: int) -> int:
	return y * width + x


func index_to_pos(idx: int) -> Vector2i:
	return Vector2i(_col(idx), _row(idx))


func get_item_at(idx: int) -> ItemInstance:
	if idx < 0 or idx >= _grid.size():
		return null
	return _grid[idx]


func get_all_items() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	result.assign(_items)
	return result


func get_occupied_slots(item: ItemInstance) -> Array[int]:
	var result: Array[int] = []
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _col(item.center_slot)
	var cy: int = _row(item.center_slot)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)
	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var slot_idx: int = (start_y + y) * width + (start_x + x)
				result.append(slot_idx)
	return result


func can_place_at(item: ItemInstance, center_idx: int, ignore_item: ItemInstance = null) -> bool:
	if center_idx < 0 or center_idx >= width * height:
		return false
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _col(center_idx)
	var cy: int = _row(center_idx)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)
	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var slot_x: int = start_x + x
				var slot_y: int = start_y + y
				if slot_x < 0 or slot_y < 0 or slot_x >= width or slot_y >= height:
					return false
				var slot_idx: int = slot_y * width + slot_x
				var occupant: ItemInstance = _grid[slot_idx]
				if occupant != null and occupant != ignore_item:
					return false
	return true


func place_at(item: ItemInstance, center_idx: int) -> bool:
	if not can_place_at(item, center_idx):
		return false
	item.center_slot = center_idx
	var occupied: Array[int] = get_occupied_slots(item)
	for slot in occupied:
		_grid[slot] = item
	if item not in _items:
		_items.append(item)
	contents_changed.emit()
	return true


## 以抓取格為錨點檢查放置可行性
## anchor_offset = 被抓取的格子在 shape 矩陣中的座標 (x, y)
## target_slot = 滑鼠釋放位置的格子索引
func can_place_at_anchor(item: ItemInstance, target_slot: int, anchor_offset: Vector2i, ignore_item: ItemInstance = null) -> bool:
	if target_slot < 0 or target_slot >= width * height:
		return false
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var tx: int = _col(target_slot)
	var ty: int = _row(target_slot)
	var start_x: int = tx - anchor_offset.x
	var start_y: int = ty - anchor_offset.y
	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var slot_x: int = start_x + x
				var slot_y: int = start_y + y
				if slot_x < 0 or slot_y < 0 or slot_x >= width or slot_y >= height:
					return false
				var slot_idx: int = slot_y * width + slot_x
				var occupant: ItemInstance = _grid[slot_idx]
				if occupant != null and occupant != ignore_item:
					return false
	return true


## 以抓取格為錨點放置物品
func place_at_anchor(item: ItemInstance, target_slot: int, anchor_offset: Vector2i) -> bool:
	if not can_place_at_anchor(item, target_slot, anchor_offset):
		return false
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var tx: int = _col(target_slot)
	var ty: int = _row(target_slot)
	var start_x: int = tx - anchor_offset.x
	var start_y: int = ty - anchor_offset.y
	# 計算 center_slot（用於序列化）
	var center_x: int = start_x + (cols >> 1)
	var center_y: int = start_y + (rows >> 1)
	item.center_slot = center_y * width + center_x
	# 寫入 grid
	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var slot_idx: int = (start_y + y) * width + (start_x + x)
				_grid[slot_idx] = item
	if item not in _items:
		_items.append(item)
	contents_changed.emit()
	return true


func add_item(item: ItemInstance) -> int:
	var slot_count := get_slot_count()
	var saved_orientation: int = item.orientation
	if item.can_rotate():
		for orientation in 4:
			item.orientation = orientation
			for center in slot_count:
				if can_place_at(item, center):
					if place_at(item, center):
						return center
	else:
		item.orientation = 0
		for center in slot_count:
			if can_place_at(item, center):
				if place_at(item, center):
					return center
	item.orientation = saved_orientation
	return -1


func remove_item(item: ItemInstance) -> void:
	var occupied: Array[int] = get_occupied_slots(item)
	for slot in occupied:
		if slot >= 0 and slot < _grid.size():
			_grid[slot] = null
	_items.erase(item)
	item.center_slot = -1
	contents_changed.emit()


func try_rotate(item: ItemInstance, clockwise: bool = true) -> bool:
	if not item.can_rotate():
		return false
	var old_orientation: int = item.orientation
	var new_orientation: int
	if clockwise:
		new_orientation = (old_orientation + 1) % 4
	else:
		new_orientation = (old_orientation + 3) % 4
	item.orientation = new_orientation
	if not can_place_at(item, item.center_slot, item):
		item.orientation = old_orientation
		return false
	# Clear old grid positions
	for i in _grid.size():
		if _grid[i] == item:
			_grid[i] = null
	# Write new grid positions
	var occupied: Array[int] = get_occupied_slots(item)
	for slot in occupied:
		_grid[slot] = item
	contents_changed.emit()
	return true


func find_item_at(idx: int) -> ItemInstance:
	if idx < 0 or idx >= _grid.size():
		return null
	return _grid[idx]


func clear_all() -> void:
	for item: ItemInstance in _items:
		item.center_slot = -1
	for i in _grid.size():
		_grid[i] = null
	_items.clear()
	contents_changed.emit()


func resize(new_width: int, new_height: int) -> void:
	var old_items: Array[ItemInstance] = []
	old_items.assign(_items)
	# Save old center slots before resetting
	var old_centers: Dictionary = {}
	for item: ItemInstance in old_items:
		old_centers[item] = item.center_slot
		item.center_slot = -1
	# Create new grid
	width = new_width
	height = new_height
	_grid.clear()
	_grid.resize(width * height)
	for i in _grid.size():
		_grid[i] = null
	_items.clear()
	# Re-place each item: prefer same center, then auto-find
	for item: ItemInstance in old_items:
		var old_center: int = old_centers[item]
		if can_place_at(item, old_center):
			place_at(item, old_center)
		else:
			var new_center := add_item(item)
			if new_center < 0:
				push_warning("[InvContainer] Item '%s' removed during resize" % item.item_id)
	contents_changed.emit()


func get_total_stats() -> Dictionary:
	var result := { "attack": 0, "defense": 0, "speed": 0 }
	for item: ItemInstance in _items:
		if item.equipped:
			var stats: Dictionary = item.get_stats()
			for key in stats:
				if result.has(key):
					result[key] += stats[key]
	return result


func serialize() -> Dictionary:
	var serialized_items: Array = []
	for item: ItemInstance in _items:
		serialized_items.append(item.serialize())
	return {
		"width": width,
		"height": height,
		"items": serialized_items,
	}


func deserialize(data: Dictionary) -> void:
	width = data.get("width", width)
	height = data.get("height", height)
	_grid.clear()
	_grid.resize(width * height)
	for i in _grid.size():
		_grid[i] = null
	_items.clear()
	if data.has("items"):
		# New format: item list with center_slot + orientation
		var serialized_items = data["items"]
		for item_data in serialized_items:
			if item_data is Dictionary:
				var item := ItemInstance.deserialize(item_data)
				var center: int = item.center_slot
				if center >= 0:
					place_at(item, center)
	else:
		# Old format: slot-by-slot array (backward compatibility)
		var serialized_slots = data.get("slots", [])
		for i in mini(serialized_slots.size(), _grid.size()):
			var slot_data = serialized_slots[i]
			if slot_data != null and slot_data is Dictionary:
				var item := ItemInstance.deserialize(slot_data)
				item.center_slot = i
				_grid[i] = item
				_items.append(item)
	contents_changed.emit()
