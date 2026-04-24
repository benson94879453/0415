extends Node

## 物品資料庫 (Autoload)
## 從 items.json 載入所有物品定義，提供查詢 API
## 包含紋理快取：首次查詢時從 icon 路徑載入圖片，自動生成 4 方向旋轉版本

var _items: Dictionary = {}  # item_id → Dictionary
var _texture_cache: Dictionary = {}  # item_id → Array[ImageTexture] (索引 0-3 = orientation)


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


## 取得物品指定方向的紋理（首次呼叫時自動載入並快取 4 方向）
## 沒有 icon 的物品回傳 null，UI 層會用 ColorRect fallback
func get_item_texture(item_id: String, orientation: int) -> ImageTexture:
	if not _items.has(item_id):
		return null
	if not _texture_cache.has(item_id):
		_load_item_textures(item_id)
	var textures: Array = _texture_cache[item_id]
	if textures.is_empty():
		return null
	return textures[orientation % 4]


## 載入並快取單個物品的 4 方向紋理
## orientation 0 = 原圖，1 = 90° CW，2 = 180°，3 = 270° CW
func _load_item_textures(item_id: String) -> void:
	var def: Dictionary = _items[item_id]
	var icon_path: String = def.get("icon", "")
	if icon_path == "":
		_texture_cache[item_id] = []
		return
	var tex: Texture2D = ResourceLoader.load(icon_path, "CompressedTexture2D")
	if tex == null:
		push_warning("[ItemDatabase] 無法載入圖片: %s" % icon_path)
		_texture_cache[item_id] = []
		return
	var image: Image = tex.get_image()
	if image == null:
		push_warning("[ItemDatabase] 無法取得圖片資料: %s" % icon_path)
		_texture_cache[item_id] = []
		return
	var textures: Array = []
	for i in 4:
		var rotated: Image = image.duplicate()
		for j in i:
			rotated.rotate_90(CLOCKWISE)
		textures.append(ImageTexture.create_from_image(rotated))
	_texture_cache[item_id] = textures
