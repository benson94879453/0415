extends Node

## Inventory Evaluator (Autoload)
## Monitors the player's inventory and calculates total stats including spatial proximity buffs.

signal stats_changed

var _inventory: PlayerInventory = null
var _cached_stats: Dictionary = {}
var _cached_attack_config: Dictionary = {}


func setup(inventory: PlayerInventory) -> void:
	if _inventory != null:
		_inventory.contents_changed.disconnect(_recalculate)
	_inventory = inventory
	_inventory.contents_changed.connect(_recalculate)
	_recalculate()


func get_total_stats() -> Dictionary:
	return _cached_stats


func get_attack_config() -> Dictionary:
	return _cached_attack_config


func _recalculate() -> void:
	if _inventory == null:
		_cached_stats = _base_stats()
		_cached_attack_config = _default_attack_config()
		stats_changed.emit()
		return

	var totals: Dictionary = _base_stats()
	var found_weapon := false
	var attack_config: Dictionary = _default_attack_config()
	var grid: Array = _inventory._grid
	var inv_width: int = _inventory.width

	var items: Array[ItemInstance] = _inventory.get_all_items()

	for item: ItemInstance in items:
		# --- add flat item stats ---
		var item_stats: Dictionary = item.get_stats()
		for key in item_stats:
			if totals.has(key):
				totals[key] += item_stats[key]
			else:
				totals[key] = item_stats[key]

		# --- capture first weapon attack config ---
		if not found_weapon:
			var def: Dictionary = item.get_definition()
			if def.get("item_category", "") == "weapon":
				var cfg: Dictionary = def.get("attack", {})
				if not cfg.is_empty():
					attack_config = cfg
					found_weapon = true

		# --- apply proximity buffs from buff_slots ---
		var def: Dictionary = item.get_definition()
		var buff_slots: Array = def.get("buff_slots", [])
		if buff_slots.is_empty():
			continue

		var center_col: int = _col(item.center_slot, inv_width)
		var center_row: int = _row(item.center_slot, inv_width)

		for buff_entry in buff_slots:
			if not buff_entry is Dictionary:
				continue
			var offset_raw: Array = buff_entry.get("offset", [0, 0])
			var dx: int = offset_raw[0]
			var dy: int = offset_raw[1]

			# rotate offset to match item orientation
			var rotated: Array = _rotate_offset(dx, dy, item.orientation)
			var rdx: int = rotated[0]
			var rdy: int = rotated[1]

			var target_col: int = center_col + rdx
			var target_row: int = center_row + rdy

			if target_col < 0 or target_col >= inv_width:
				continue
			if target_row < 0 or target_row >= _inventory.height:
				continue

			var target_idx: int = target_row * inv_width + target_col
			if target_idx < 0 or target_idx >= grid.size():
				continue
			if grid[target_idx] == null:
				continue

			# target cell has an item — apply buff values
			for stat_key in ["attack", "defense", "speed", "attack_speed_multiplier", "max_hp", "max_mp"]:
				if buff_entry.has(stat_key):
					if totals.has(stat_key):
						totals[stat_key] += buff_entry[stat_key]
					else:
						totals[stat_key] = buff_entry[stat_key]

	_cached_stats = totals
	_cached_attack_config = attack_config
	stats_changed.emit()


## Rotate an offset [dx, dy] by orientation steps of 90° CW.
## 90° CW in screen coordinates (y-down): [dx, dy] → [-dy, dx]
static func _rotate_offset(dx: int, dy: int, orientation: int) -> Array:
	var rx: int = dx
	var ry: int = dy
	for _i in range(orientation % 4):
		var tmp: int = rx
		rx = -ry
		ry = tmp
	return [rx, ry]


static func _col(idx: int, w: int) -> int:
	return idx % w


static func _row(idx: int, w: int) -> int:
	return floori(idx / float(w))


static func _base_stats() -> Dictionary:
	return {
		"attack": 0,
		"defense": 0,
		"speed": 0,
		"attack_speed_multiplier": 1.0,
		"max_hp": 100,
		"max_mp": 50,
	}


static func _default_attack_config() -> Dictionary:
	return {
		"type": "melee",
		"cooldown": 1.0,
		"range": 50.0,
		"arc_deg": 90,
	}
