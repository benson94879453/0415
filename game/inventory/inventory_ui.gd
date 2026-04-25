class_name InventoryUI
extends CanvasLayer

## 當物品從背包中丟棄時發出（拖出面板或按 Q 鍵）
signal item_dropped_from_inventory(item: ItemInstance)

## 當藍圖被拖到插槽圖示上時發出
signal blueprint_applied_to_slot(item: ItemInstance, slot_index: int)

## 背包 UI
## 格子背景 (_grid_container) 與物品圖層 (_item_layer) 分離
## 物品圖層使用 TextureRect 跨越多格顯示，mouse_filter=IGNORE 讓點擊穿透到格子
## 沒有 icon 的物品自動 fallback 為 ColorRect（用 icon_color）

const SLOT_SIZE := 128.0
const SLOT_PADDING := 6.0
const SLOT_GAP := 3.0

var _inventory: PlayerInventory
var _is_open: bool = false
var _slot_controls: Array = []  # Array of Panel（純背景）
var _dragging: bool = false
var _drag_item: ItemInstance = null
var _drag_original_center: int = -1
var _drag_original_orientation: int = 0
var _drag_anchor: Vector2i = Vector2i.ZERO  ## 被抓取格在 shape 矩陣中的座標
var _drag_icon_offset: Vector2 = Vector2.ZERO  ## drag icon 偏移量（讓抓取格對齊滑鼠）
var _hover_slot: int = -1  ## 拖曳中滑鼠懸停的格子索引（-1 = 無）
var _hovered_item_slot: int = -1  ## 非拖曳狀態下，滑鼠懸停的格子索引（供 Q 鍵丟棄使用）
var _drag_icon: Control
var _grid_container: GridContainer
var _item_layer: Control  ## 物品紋理圖層，疊在 grid 正上方
var _tooltip: Label
var _panel: Panel
var _bg_overlay: ColorRect
var _dungeon_slots: Array = []  # Slot data from dungeon
var _slot_icon_panel: HBoxContainer  # Container for slot icons above inventory
var _slot_icon_controls: Array = []  # Array of Panel nodes for slot icons
var _hovered_slot_icon: int = -1  # Which slot icon the mouse is over during drag


## 格子索引 → 列號（避免 integer division 警告）
func _slot_col(idx: int) -> int:
	return idx % _inventory.width


## 格子索引 → 行號（避免 integer division 警告）
func _slot_row(idx: int) -> int:
	return floori(idx / float(_inventory.width))


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Full-screen semi-transparent overlay
	_bg_overlay = ColorRect.new()
	_bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_overlay.color = Color(0, 0, 0, 0.4)
	_bg_overlay.visible = false
	add_child(_bg_overlay)

	# Main centered panel
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.visible = false
	add_child(_panel)

	# Title
	var title := Label.new()
	title.text = "背包"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	_panel.add_child(title)

	# Grid container — 純背景格子，不攔截滑鼠（點擊由 slot Panel 處理）
	_grid_container = GridContainer.new()
	_grid_container.add_theme_constant_override("h_separation", int(SLOT_GAP))
	_grid_container.add_theme_constant_override("v_separation", int(SLOT_GAP))
	_panel.add_child(_grid_container)

	# Item layer — 疊在 grid 上方，顯示跨格物品紋理，不攔截滑鼠
	_item_layer = Control.new()
	_item_layer.name = "ItemLayer"
	_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_item_layer)

	# Floating tooltip
	_tooltip = Label.new()
	_tooltip.add_theme_font_size_override("font_size", 13)
	_tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tooltip.add_theme_constant_override("outline_size", 2)
	_tooltip.visible = false
	_tooltip.z_index = 5
	add_child(_tooltip)

	# Drag icon (shape-following preview following mouse)
	_drag_icon = Control.new()
	_drag_icon.z_index = 100
	_drag_icon.visible = false
	add_child(_drag_icon)

	# Slot icon panel — shown above inventory when dragging blueprints
	_slot_icon_panel = HBoxContainer.new()
	_slot_icon_panel.name = "SlotIconPanel"
	_slot_icon_panel.visible = false
	add_child(_slot_icon_panel)


func setup(inv: PlayerInventory) -> void:
	_inventory = inv
	_rebuild_grid()
	_inventory.contents_changed.connect(_on_contents_changed)


func toggle() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_bg_overlay.visible = _is_open
	_tooltip.visible = false
	_hovered_item_slot = -1
	if _is_open:
		_refresh_items()


func _rebuild_grid() -> void:
	for child in _grid_container.get_children():
		child.queue_free()
	_slot_controls.clear()

	_grid_container.columns = _inventory.width

	for i in _inventory.get_slot_count():
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.name = "Slot_%d" % i

		# Per-slot style (unique instance so we can modify individually)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
		style.border_color = Color(0.4, 0.4, 0.5)
		style.set_border_width_all(1)
		style.set_content_margin_all(SLOT_PADDING)
		slot.add_theme_stylebox_override("panel", style)

		_grid_container.add_child(slot)
		_slot_controls.append(slot)

	_update_panel_size()
	_refresh_items()


func _update_panel_size() -> void:
	var grid_w := _inventory.width * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var grid_h := _inventory.height * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var panel_w := grid_w + 20.0
	var panel_h := grid_h + 50.0

	_panel.offset_left = -panel_w * 0.5
	_panel.offset_top = -panel_h * 0.5
	_panel.offset_right = panel_w * 0.5
	_panel.offset_bottom = panel_h * 0.5

	# Position title at top of panel
	var title: Label = _panel.get_child(0)
	title.offset_left = 0.0
	title.offset_top = 5.0
	title.offset_right = panel_w
	title.offset_bottom = 28.0

	# Position grid below title
	_grid_container.offset_left = 10.0
	_grid_container.offset_top = 33.0
	_grid_container.offset_right = 10.0 + grid_w
	_grid_container.offset_bottom = 33.0 + grid_h

	# Item layer — 與 grid 完全對齊，疊在上方
	_item_layer.offset_left = _grid_container.offset_left
	_item_layer.offset_top = _grid_container.offset_top
	_item_layer.offset_right = _grid_container.offset_right
	_item_layer.offset_bottom = _grid_container.offset_bottom


func _on_contents_changed() -> void:
	if _slot_controls.size() != _inventory.get_slot_count():
		_rebuild_grid()
	else:
		_refresh_items()


func _refresh_items() -> void:
	for child in _item_layer.get_children():
		child.queue_free()

	if _inventory == null:
		return

	# 第一層：渲染所有物品（拖曳中的物品跳過，改用影子）
	for item: ItemInstance in _inventory.get_all_items():
		if item == _drag_item:
			continue
		_add_item_visual(item)

	# 第二層：拖曳中的原位灰白影子
	if _dragging and _drag_item != null:
		_add_ghost_visual()

	# 第三層：懸停放置預覽（綠/紅半透明色塊）
	if _dragging and _drag_item != null and _hover_slot >= 0:
		_add_preview_visual()


## 在 _item_layer 中為一個物品建立視覺元素（非拖曳中）
## 1) 裝備中 → 綠色邊框 Panel（底層）
## 2) 有 icon → TextureRect（或無 icon → ColorRect fallback）
func _add_item_visual(item: ItemInstance) -> void:
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _slot_col(item.center_slot)
	var cy: int = _slot_row(item.center_slot)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)

	var pos_x: float = start_x * (SLOT_SIZE + SLOT_GAP)
	var pos_y: float = start_y * (SLOT_SIZE + SLOT_GAP)
	var size_x: float = cols * SLOT_SIZE + (cols - 1) * SLOT_GAP
	var size_y: float = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP

	# Equipped highlight — 綠色邊框疊在物品後方
	if item.equipped:
		var highlight := Panel.new()
		var h_style := StyleBoxFlat.new()
		h_style.bg_color = Color(0, 0, 0, 0)
		h_style.border_color = Color(0.2, 0.8, 0.3)
		h_style.set_border_width_all(2)
		h_style.set_content_margin_all(0)
		highlight.add_theme_stylebox_override("panel", h_style)
		highlight.position = Vector2(pos_x, pos_y)
		highlight.size = Vector2(size_x, size_y)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_item_layer.add_child(highlight)

	# 物品圖示
	var tex: ImageTexture = ItemDatabase.get_item_texture(item.item_id, item.orientation)
	if tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = tex
		icon_rect.position = Vector2(pos_x, pos_y)
		icon_rect.size = Vector2(size_x, size_y)
		icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_item_layer.add_child(icon_rect)
	else:
		# Fallback：用 icon_color 畫色塊（無圖片的物品）
		var def := item.get_definition()
		var color_array: Array = def.get("icon_color", [0.5, 0.5, 0.5])
		var cr := ColorRect.new()
		cr.color = Color(color_array[0], color_array[1], color_array[2])
		cr.position = Vector2(pos_x, pos_y)
		cr.size = Vector2(size_x, size_y)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_item_layer.add_child(cr)


## 拖曳中的原位影子 — 半透明灰白色塊，標示物品原始位置
func _add_ghost_visual() -> void:
	# 用原始方向計算 shape（拖曳中 orientation 可能已被旋轉）
	var saved_ori: int = _drag_item.orientation
	_drag_item.orientation = _drag_original_orientation
	var shape: Array = _drag_item.get_rotated_shape()
	_drag_item.orientation = saved_ori

	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _slot_col(_drag_original_center)
	var cy: int = _slot_row(_drag_original_center)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)

	var ghost_color := Color(0.8, 0.8, 0.8, 0.3)
	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var sx: int = start_x + x
				var sy: int = start_y + y
				if sx >= 0 and sy >= 0 and sx < _inventory.width and sy < _inventory.height:
					var cr := ColorRect.new()
					cr.color = ghost_color
					cr.position = Vector2(sx * (SLOT_SIZE + SLOT_GAP), sy * (SLOT_SIZE + SLOT_GAP))
					cr.size = Vector2(SLOT_SIZE, SLOT_SIZE)
					cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
					_item_layer.add_child(cr)


## 拖曳中的放置預覽 — 半透明色塊顯示物品落點
## 放得下 → 綠色，放不下 → 紅色
func _add_preview_visual() -> void:
	var shape: Array = _drag_item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var tx: int = _slot_col(_hover_slot)
	var ty: int = _slot_row(_hover_slot)
	var start_x: int = tx - _drag_anchor.x
	var start_y: int = ty - _drag_anchor.y

	# 判斷放置是否合法（忽略自身佔位）
	var valid: bool = _inventory.can_place_at_anchor(_drag_item, _hover_slot, _drag_anchor, _drag_item)
	var preview_color := Color(0.2, 0.8, 0.3, 0.35) if valid else Color(0.8, 0.2, 0.2, 0.35)

	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var sx: int = start_x + x
				var sy: int = start_y + y
				if sx >= 0 and sy >= 0 and sx < _inventory.width and sy < _inventory.height:
					var cr := ColorRect.new()
					cr.color = preview_color
					cr.position = Vector2(sx * (SLOT_SIZE + SLOT_GAP), sy * (SLOT_SIZE + SLOT_GAP))
					cr.size = Vector2(SLOT_SIZE, SLOT_SIZE)
					cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
					_item_layer.add_child(cr)


func _process(_delta: float) -> void:
	if _dragging and _drag_icon.visible:
		_drag_icon.global_position = get_viewport().get_mouse_position() - _drag_icon_offset
		# 即時追蹤滑鼠所在的格子，用於放置預覽
		var new_hover := _get_slot_at_position(get_viewport().get_mouse_position())
		if new_hover != _hover_slot:
			_hover_slot = new_hover
			_refresh_items()
	# Update slot icon hover state
	if _dragging and _drag_item != null and _is_blueprint_item(_drag_item) and _slot_icon_panel != null and _slot_icon_panel.visible:
		var new_hover := _get_hit_slot_icon(get_viewport().get_mouse_position())
		if new_hover != _hovered_slot_icon:
			_hovered_slot_icon = new_hover
			_update_slot_icon_highlights()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		if _dragging:
			_cancel_drag()
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
		return

	if event.is_action_pressed("dropitem") and not _dragging:
		_drop_hovered_item()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_handle_rotation()
		get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_left_click(event)
		else:
			_on_left_release(event)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_on_right_click(event)


func _on_left_click(event: InputEventMouseButton) -> void:
	var idx := _get_slot_at_position(event.global_position)
	if idx < 0:
		return
	var item: ItemInstance = _inventory.find_item_at(idx)
	if item != null:
		var anchor := _compute_anchor(idx, item)
		_start_drag(item, anchor)


func _on_left_release(event: InputEventMouseButton) -> void:
	if not _dragging:
		return
	# Check if dropped on a slot icon (blueprint targeting)
	if _slot_icon_panel != null and _slot_icon_panel.visible and _drag_item != null:
		if _is_blueprint_item(_drag_item):
			var hit_slot := _get_hit_slot_icon(event.global_position)
			if hit_slot >= 0:
				_apply_blueprint_to_slot_icon(hit_slot)
				return
	var target_slot := _get_slot_at_position(event.global_position)
	if target_slot < 0:
		if _is_outside_panel(event.global_position):
			_end_drag(-1)
		else:
			# Mouse is between slots but inside panel — treat as no-move
			_end_drag(_drag_original_center)
	else:
		_end_drag(target_slot)


func _on_right_click(event: InputEventMouseButton) -> void:
	var idx := _get_slot_at_position(event.global_position)
	if idx < 0:
		return
	var item: ItemInstance = _inventory.find_item_at(idx)
	if item == null:
		return
	if item.is_consumable():
		_inventory.use_consumable(idx)
	else:
		_inventory.toggle_equip(idx)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging:
		_tooltip.visible = false
		return
	_hovered_item_slot = -1
	var idx := _get_slot_at_position(event.global_position)
	if idx >= 0:
		var item: ItemInstance = _inventory.find_item_at(idx)
		if item != null:
			_hovered_item_slot = idx
			var item_name := item.get_display_name()
			var def := item.get_definition()
			var desc: String = def.get("description", "")
			_tooltip.text = item_name + "\n" + desc if desc != "" else item_name
			_tooltip.visible = true
			_tooltip.global_position = event.global_position + Vector2(15.0, 15.0)
		else:
			_tooltip.visible = false
	else:
		_tooltip.visible = false


func _handle_rotation() -> void:
	if not _dragging or _drag_item == null:
		return
	if _drag_item.can_rotate():
		# 旋轉 anchor 座標：90° CW 後 (ax, ay) → (old_rows-1-ay, ax)
		var old_shape: Array = _drag_item.get_rotated_shape()
		var old_rows: int = old_shape.size()
		var new_anchor := Vector2i(old_rows - 1 - _drag_anchor.y, _drag_anchor.x)
		_drag_anchor = new_anchor
		_drag_item.orientation = (_drag_item.orientation + 1) % 4
		_update_drag_icon()
		_refresh_items()


func _start_drag(item: ItemInstance, anchor: Vector2i) -> void:
	_dragging = true
	_drag_item = item
	_drag_original_center = item.center_slot
	_drag_original_orientation = item.orientation
	_drag_anchor = anchor
	_update_drag_icon()
	_drag_icon.visible = true
	_drag_icon.global_position = get_viewport().get_mouse_position() - _drag_icon_offset
	_refresh_items()
	# Show slot icons if dragging a blueprint and dungeon has slots
	if _is_blueprint_item(item) and not _dungeon_slots.is_empty():
		_rebuild_slot_icons()
		_slot_icon_panel.visible = true


func _update_drag_icon() -> void:
	if _drag_item == null:
		return
	# 清除舊的預覽（先移除再釋放，避免旋轉時新舊同時閃現）
	var old_children := _drag_icon.get_children()
	for child in old_children:
		_drag_icon.remove_child(child)
		child.queue_free()

	var shape: Array = _drag_item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cell_size := SLOT_SIZE * 0.8
	var gap := SLOT_GAP * 0.8

	_drag_icon.size = Vector2(cols * cell_size + (cols - 1) * gap, rows * cell_size + (rows - 1) * gap)

	# 優先使用 TextureRect 顯示物品紋理
	var tex: ImageTexture = ItemDatabase.get_item_texture(_drag_item.item_id, _drag_item.orientation)
	if tex != null:
		var drag_rect := TextureRect.new()
		drag_rect.texture = tex
		drag_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		drag_rect.stretch_mode = TextureRect.STRETCH_SCALE
		drag_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		drag_rect.modulate.a = 0.7
		drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drag_icon.add_child(drag_rect)
	else:
		# Fallback：逐格 ColorRect
		var def := _drag_item.get_definition()
		var color_array: Array = def.get("icon_color", [0.5, 0.5, 0.5])
		var item_color := Color(color_array[0], color_array[1], color_array[2], 0.7)
		for y in rows:
			var row: Array = shape[y] as Array
			for x in cols:
				if row[x] == 1:
					var cell := ColorRect.new()
					cell.color = item_color
					cell.position = Vector2(x * (cell_size + gap), y * (cell_size + gap))
					cell.size = Vector2(cell_size, cell_size)
					_drag_icon.add_child(cell)

	# 偏移：讓 anchor 格的中心對齊滑鼠
	_drag_icon_offset = Vector2(
		_drag_anchor.x * (cell_size + gap) + cell_size * 0.5,
		_drag_anchor.y * (cell_size + gap) + cell_size * 0.5
	)


func _end_drag(target_slot: int) -> void:
	var item := _drag_item
	if item == null:
		_clear_drag()
		return

	var old_center: int = _drag_original_center
	var old_orientation: int = _drag_original_orientation
	var new_orientation: int = item.orientation

	# 恢復舊方向 — 所有 remove_item 必須在舊方向下執行
	item.orientation = old_orientation

	# Dropped outside panel → transfer to ground via signal
	if target_slot < 0:
		_inventory.remove_item(item)
		item_dropped_from_inventory.emit(item)
		_clear_drag()
		return

	# 用舊方向查 grid（grid 裡是舊方向的位置）
	var target_item: ItemInstance = _inventory.find_item_at(target_slot)

	# 先移除（舊方向），再放置（新方向）
	_inventory.remove_item(item)
	item.orientation = new_orientation

	if target_item == item or target_item == null:
		# Released on self or empty slot → try anchor placement
		if not _inventory.place_at_anchor(item, target_slot, _drag_anchor):
			# 放置失敗，退回原位
			item.orientation = old_orientation
			if not _inventory.place_at(item, old_center):
				_inventory.add_item(item)
		_clear_drag()
		return

	# Target has a different item → try swap
	_try_swap(item, target_item, target_slot, old_center, old_orientation, new_orientation)
	_clear_drag()


func _cancel_drag() -> void:
	if _drag_item != null:
		_drag_item.orientation = _drag_original_orientation
	_clear_drag()


func _clear_drag() -> void:
	_dragging = false
	_drag_item = null
	_drag_original_center = -1
	_drag_original_orientation = 0
	_hover_slot = -1
	_hovered_item_slot = -1
	_drag_icon.visible = false
	_tooltip.visible = false
	# Hide slot icons
	if _slot_icon_panel != null:
		_slot_icon_panel.visible = false
	_hovered_slot_icon = -1
	_refresh_items()


func _drop_hovered_item() -> void:
	if _hovered_item_slot < 0:
		return
	var item: ItemInstance = _inventory.find_item_at(_hovered_item_slot)
	if item == null:
		return
	# 清除此物品在 hotbar 中的綁定
	for i in _inventory.hotbar.size():
		if _inventory.hotbar[i] == item.center_slot:
			_inventory.hotbar[i] = -1
	_inventory.remove_item(item)
	item_dropped_from_inventory.emit(item)
	_hovered_item_slot = -1


func _try_move(item: ItemInstance, target_slot: int, old_center: int, old_orientation: int, _new_orientation: int) -> void:
	# item 已在 _end_drag 中移除，orientation 已設為 new_orientation
	if _inventory.place_at_anchor(item, target_slot, _drag_anchor):
		return
	# Anchor 放置失敗 — auto-find
	if _inventory.add_item(item) >= 0:
		return
	# Auto-find 也失敗 — 退回原位
	item.orientation = old_orientation
	_inventory.place_at(item, old_center)


func _try_swap(drag_item: ItemInstance, other_item: ItemInstance, target_slot: int, drag_old_center: int, drag_old_orientation: int, _drag_new_orientation: int) -> void:
	var other_old_center: int = other_item.center_slot

	# drag_item 已在 _end_drag 中以舊方向 remove，orientation 已設為 new_orientation
	_inventory.remove_item(other_item)

	# drag_item orientation 已是 new_orientation，直接放置

	# Try placing dragged item at target with anchor
	if _inventory.place_at_anchor(drag_item, target_slot, _drag_anchor):
		# Try placing other item at the dragged item's old center
		if _inventory.place_at(other_item, drag_old_center):
			return
		# Other item can't go to old center — auto-find
		if _inventory.add_item(other_item) >= 0:
			return
		# Total revert
		_inventory.remove_item(drag_item)
		drag_item.orientation = drag_old_orientation
		_inventory.place_at(drag_item, drag_old_center)
		_inventory.place_at(other_item, other_old_center)
	else:
		# Dragged item can't go to target — try auto-find
		if _inventory.add_item(drag_item) >= 0:
			# Try placing other item back at its original position
			if _inventory.place_at(other_item, other_old_center):
				return
			_inventory.add_item(other_item)
		else:
			# Complete revert
			drag_item.orientation = drag_old_orientation
			_inventory.place_at(drag_item, drag_old_center)
			_inventory.place_at(other_item, other_old_center)


func _get_slot_at_position(global_pos: Vector2) -> int:
	for i in _slot_controls.size():
		var slot: Control = _slot_controls[i]
		var rect := Rect2(slot.global_position, slot.size)
		if rect.has_point(global_pos):
			return i
	return -1


func _is_outside_panel(global_pos: Vector2) -> bool:
	if _panel == null:
		return true
	var panel_rect := Rect2(_panel.global_position, _panel.size)
	return not panel_rect.has_point(global_pos)


## 計算被點擊的格子在 shape 矩陣中的座標
## clicked_slot = 點擊的格子索引
## item = 該格子上的物品（必須已放置，center_slot 有效）
func _compute_anchor(clicked_slot: int, item: ItemInstance) -> Vector2i:
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _slot_col(item.center_slot)
	var cy: int = _slot_row(item.center_slot)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)
	var click_x: int = _slot_col(clicked_slot)
	var click_y: int = _slot_row(clicked_slot)
	return Vector2i(click_x - start_x, click_y - start_y)


func _is_blueprint_item(item: ItemInstance) -> bool:
	var def := item.get_definition()
	return def.get("item_category", "") == "blueprint"


func set_dungeon_slots(slots_data: Array) -> void:
	_dungeon_slots = slots_data


func _rebuild_slot_icons() -> void:
	# Clear old icons
	for child in _slot_icon_panel.get_children():
		child.queue_free()
	_slot_icon_controls.clear()

	if _dungeon_slots.is_empty():
		return

	var icon_size := 110.0
	var gap := 12.0
	_slot_icon_panel.add_theme_constant_override("separation", int(gap))

	for i in _dungeon_slots.size():
		var slot_data: Dictionary = _dungeon_slots[i]
		var is_blank: bool = slot_data.get("is_blank", true)

		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(icon_size, icon_size)

		var style := StyleBoxFlat.new()
		if is_blank:
			style.bg_color = Color(0.25, 0.25, 0.3, 0.9)
		else:
			style.bg_color = Color(0.4, 0.3, 0.2, 0.9)
		style.border_color = Color(0.4, 0.4, 0.5)
		style.set_border_width_all(1)
		style.set_content_margin_all(4)
		panel.add_theme_stylebox_override("panel", style)

		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)
		if is_blank:
			lbl.text = "空白牆"
		else:
			lbl.text = "門"
		panel.add_child(lbl)

		_slot_icon_panel.add_child(panel)
		_slot_icon_controls.append(panel)

	# Position above the inventory panel
	var total_width := _dungeon_slots.size() * icon_size + (_dungeon_slots.size() - 1) * gap
	_slot_icon_panel.offset_left = -total_width * 0.5
	_slot_icon_panel.offset_top = _panel.offset_top - 12.0 - icon_size
	_slot_icon_panel.offset_right = total_width * 0.5
	_slot_icon_panel.offset_bottom = _panel.offset_top - 12.0


func _get_hit_slot_icon(global_pos: Vector2) -> int:
	if _slot_icon_panel == null or not _slot_icon_panel.visible:
		return -1
	for i in _slot_icon_controls.size():
		var ctrl: Control = _slot_icon_controls[i]
		var rect := Rect2(ctrl.global_position, ctrl.size)
		if rect.has_point(global_pos):
			return i
	return -1


func _apply_blueprint_to_slot_icon(icon_index: int) -> void:
	if icon_index < 0 or icon_index >= _dungeon_slots.size():
		_cancel_drag()
		return
	var item := _drag_item
	if item == null or not _is_blueprint_item(item):
		_cancel_drag()
		return
	var slot_data: Dictionary = _dungeon_slots[icon_index]
	_inventory.remove_item(item)
	blueprint_applied_to_slot.emit(item, slot_data["slot_index"])
	_clear_drag()


func _update_slot_icon_highlights() -> void:
	for i in _slot_icon_controls.size():
		var panel: Panel = _slot_icon_controls[i]
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if style:
			var new_style := style.duplicate()
			if i == _hovered_slot_icon:
				new_style.border_color = Color(0.8, 0.8, 0.2)
				new_style.set_border_width_all(3)
			else:
				new_style.border_color = Color(0.4, 0.4, 0.5)
				new_style.set_border_width_all(1)
			panel.add_theme_stylebox_override("panel", new_style)
