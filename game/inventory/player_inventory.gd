class_name PlayerInventory
extends InvContainer

## 玩家專用背包
## 預設 5×5，支援裝備標記、快捷列綁定、套裝計算

const DEFAULT_WIDTH := 5
const DEFAULT_HEIGHT := 5
const HOTBAR_SIZE := 5

var hotbar: Array = []  # Array of int — item center_slot bound to hotbar, -1 = empty


func _init(p_width: int = DEFAULT_WIDTH, p_height: int = DEFAULT_HEIGHT) -> void:
	super(p_width, p_height)
	hotbar.resize(HOTBAR_SIZE)
	for i in HOTBAR_SIZE:
		hotbar[i] = -1


## 切換裝備狀態（傳入格子索引，自動找到對應物品）
func toggle_equip(idx: int) -> void:
	var item: ItemInstance = find_item_at(idx)
	if item == null:
		return
	if item.is_consumable():
		return
	item.equipped = not item.equipped
	contents_changed.emit()


## 使用消耗品（從背包移除並回傳效果）
func use_consumable(idx: int) -> Dictionary:
	var item: ItemInstance = find_item_at(idx)
	if item == null:
		return {}
	if not item.is_consumable():
		return {}
	var def := item.get_definition()
	var effects: Array = def.get("effects", [])
	# 清除此物品在 hotbar 中的綁定
	for i in hotbar.size():
		if hotbar[i] == item.center_slot:
			hotbar[i] = -1
	remove_item(item)
	return { "effects": effects }


## 綁定快捷列（hotbar_idx → 物品所在的 center_slot）
func set_hotbar_slot(hotbar_idx: int, inventory_center: int) -> void:
	if hotbar_idx < 0 or hotbar_idx >= HOTBAR_SIZE:
		return
	hotbar[hotbar_idx] = inventory_center
	contents_changed.emit()


## 取得快捷列對應的物品
func get_hotbar_item(hotbar_idx: int) -> ItemInstance:
	var center: int = hotbar[hotbar_idx] if hotbar_idx < hotbar.size() else -1
	if center < 0:
		return null
	return find_item_at(center)


## 計算套裝加成
func get_set_bonuses() -> Dictionary:
	var set_counts: Dictionary = {}
	for item: ItemInstance in get_all_items():
		if item.equipped:
			var def := item.get_definition()
			var set_id: String = def.get("set_id", "")
			if set_id != "":
				if not set_counts.has(set_id):
					set_counts[set_id] = 0
				set_counts[set_id] += 1
	return set_counts


## 覆寫序列化以包含 hotbar
func serialize() -> Dictionary:
	var result := super.serialize()
	result["hotbar"] = hotbar.duplicate()
	return result


## 覆寫反序列化以還原 hotbar
func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	var saved_hotbar = data.get("hotbar", [])
	for i in mini(saved_hotbar.size(), HOTBAR_SIZE):
		hotbar[i] = saved_hotbar[i]
