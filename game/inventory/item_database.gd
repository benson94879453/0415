extends Node

## 物品資料庫 (Autoload)
## 從 items.json 載入所有物品定義，提供查詢 API

var _items: Dictionary = {}  # item_id → Dictionary


func _ready() -> void:
	_load_items()


func _load_items() -> void:
	var file := FileAccess.open("res://game/data/items.json", FileAccess.READ)
	if file == null:
		push_warning("[ItemDatabase] 無法開啟 items.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_warning("[ItemDatabase] items.json 解析失敗: %s" % json.get_error_message())
		return
	var data = json.data
	if data is Dictionary:
		_items = data
	else:
		push_warning("[ItemDatabase] items.json 格式不正確")


## 取得物品定義
func get_item(item_id: String) -> Dictionary:
	return _items.get(item_id, {})


## 取得所有物品 ID
func get_all_ids() -> Array:
	return _items.keys()


## 檢查物品是否存在
func has_item(item_id: String) -> bool:
	return item_id in _items
