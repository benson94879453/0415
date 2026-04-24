class_name ItemInstance
extends RefCounted

## 物品實例 — 代表背包中的一個物品
## 輕量級物件，透過 item_id 查詢 ItemDatabase 取得定義資料
## 支援多格形狀（shape）與 4 方向旋轉（orientation 0-3）

var item_id: String = ""       ## 對應 items.json 的 key
var equipped: bool = false     ## 是否為「裝備中」狀態
var orientation: int = 0       ## 旋轉方向：0=0°, 1=90°CW, 2=180°, 3=270°CW
var center_slot: int = -1      ## 在容器中的中心格索引（-1 = 未放置）
var metadata: Dictionary = {}  ## 執行時附加資料（耐久、強化等）


func _init(p_id: String = "", p_equipped: bool = false, p_orientation: int = 0) -> void:
	item_id = p_id
	equipped = p_equipped
	orientation = p_orientation


## 取得此物品的定義資料（從 ItemDatabase 查詢）
func get_definition() -> Dictionary:
	return ItemDatabase.get_item(item_id)


## 取得顯示名稱
func get_display_name() -> String:
	var def := get_definition()
	if def.is_empty():
		return "???"
	return def.get("name", "???")


## 是否為消耗品
func is_consumable() -> bool:
	var def := get_definition()
	return def.get("type", "") == "consumable"


## 是否可以旋轉
func can_rotate() -> bool:
	var def := get_definition()
	return def.get("can_rotate", false)


## 取得 stats 字典
func get_stats() -> Dictionary:
	var def := get_definition()
	return def.get("stats", {})


## 取得基礎形狀（未旋轉）
func get_base_shape() -> Array:
	var def := get_definition()
	return def.get("shape", [[1]])


## 取得當前旋轉後的形狀
func get_rotated_shape() -> Array:
	return rotate_shape(get_base_shape(), orientation)


## 取得形狀佔用的格子數
func get_shape_cell_count() -> int:
	var shape := get_base_shape()
	var count := 0
	for row in shape:
		for cell in row:
			if cell == 1:
				count += 1
	return count


## ── 靜態旋轉工具 ──

## 將形狀矩陣順時針旋轉 90°
## 演算法：transpose → reverse each row
static func rotate_90_cw(shape: Array) -> Array:
	var rows := shape.size()
	if rows == 0:
		return shape
	var cols: int = (shape[0] as Array).size()
	var result: Array = []
	for x in cols:
		var new_row: Array = []
		for y in range(rows - 1, -1, -1):
			new_row.append(shape[y][x])
		result.append(new_row)
	return result


## 將形狀旋轉 orientation 次 90° CW
static func rotate_shape(shape: Array, p_orientation: int) -> Array:
	var result := shape
	var times := p_orientation % 4
	for _i in times:
		result = rotate_90_cw(result)
	return result


## ── 序列化 ──

func serialize() -> Dictionary:
	var result := { "item_id": item_id, "equipped": equipped }
	if orientation != 0:
		result["orientation"] = orientation
	if center_slot >= 0:
		result["center_slot"] = center_slot
	if not metadata.is_empty():
		result["metadata"] = metadata
	return result


static func deserialize(data: Dictionary) -> ItemInstance:
	var inst := ItemInstance.new(
		data.get("item_id", ""),
		data.get("equipped", false),
		data.get("orientation", 0),
	)
	inst.center_slot = data.get("center_slot", -1)
	if data.has("metadata"):
		inst.metadata = data["metadata"]
	return inst
