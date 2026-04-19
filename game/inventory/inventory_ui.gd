class_name InventoryUI
extends CanvasLayer

const SLOT_SIZE := 102.0
const SLOT_PADDING := 6.0
const SLOT_GAP := 3.0

var _inventory: PlayerInventory
var _is_open: bool = false
var _slot_controls: Array = []  # Array of Panel
var _dragging: bool = false
var _drag_item: ItemInstance = null
var _drag_original_center: int = -1
var _drag_original_orientation: int = 0
var _drag_anchor: Vector2i = Vector2i.ZERO  ## 被抓取格在 shape 矩陣中的座標
var _drag_icon_offset: Vector2 = Vector2.ZERO  ## drag icon 偏移量（讓抓取格對齊滑鼠）
var _drag_icon: Control
var _grid_container: GridContainer
var _tooltip: Label
var _panel: Panel
var _bg_overlay: ColorRect


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

	# Grid container for slot panels
	_grid_container = GridContainer.new()
	_grid_container.add_theme_constant_override("h_separation", SLOT_GAP)
	_grid_container.add_theme_constant_override("v_separation", SLOT_GAP)
	_panel.add_child(_grid_container)

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


func setup(inv: PlayerInventory) -> void:
	_inventory = inv
	_rebuild_grid()
	_inventory.contents_changed.connect(_on_contents_changed)


func toggle() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_bg_overlay.visible = _is_open
	if _is_open:
		_refresh_all_slots()


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

		# Color rect for item icon fill
		var icon := ColorRect.new()
		icon.name = "Icon"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.visible = false
		slot.add_child(icon)

		# Label for item display name
		var label := Label.new()
		label.name = "Label"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 1)
		slot.add_child(label)

		_grid_container.add_child(slot)
		_slot_controls.append(slot)

	_update_panel_size()


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


func _on_contents_changed() -> void:
	if _slot_controls.size() != _inventory.get_slot_count():
		_rebuild_grid()
	else:
		_refresh_all_slots()


func _refresh_all_slots() -> void:
	for i in _slot_controls.size():
		_refresh_slot(i)


func _refresh_slot(idx: int) -> void:
	if idx >= _slot_controls.size():
		return
	var slot: Panel = _slot_controls[idx]
	var icon: ColorRect = slot.get_node("Icon")
	var label: Label = slot.get_node("Label")
	var item: ItemInstance = _inventory.find_item_at(idx)
	var style: StyleBoxFlat = slot.get_theme_stylebox("panel") as StyleBoxFlat

	# Reset modulation
	slot.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if item == null:
		icon.visible = false
		label.text = ""
		style.border_color = Color(0.4, 0.4, 0.5)
		style.set_border_width_all(1)
		return

	# Item present at this slot
	var def := item.get_definition()
	var color_array: Array = def.get("icon_color", [0.5, 0.5, 0.5])
	icon.color = Color(color_array[0], color_array[1], color_array[2])
	icon.visible = true
	label.text = ""

	# Equipped highlight: green border on all occupied slots
	if item.equipped:
		style.border_color = Color(0.2, 0.8, 0.3)
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.4, 0.4, 0.5)
		style.set_border_width_all(1)

	# Dim slots of the item currently being dragged
	if item == _drag_item:
		slot.modulate.a = 0.3


func _process(_delta: float) -> void:
	if _dragging and _drag_icon.visible:
		_drag_icon.global_position = get_viewport().get_mouse_position() - _drag_icon_offset


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		if _dragging:
			_cancel_drag()
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
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
	var idx := _get_slot_at_position(event.global_position)
	if idx >= 0:
		var item: ItemInstance = _inventory.find_item_at(idx)
		if item != null:
			var name := item.get_display_name()
			var def := item.get_definition()
			var desc: String = def.get("description", "")
			_tooltip.text = name + "\n" + desc if desc != "" else name
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
		_refresh_all_slots()


func _start_drag(item: ItemInstance, anchor: Vector2i) -> void:
	_dragging = true
	_drag_item = item
	_drag_original_center = item.center_slot
	_drag_original_orientation = item.orientation
	_drag_anchor = anchor
	_update_drag_icon()
	_drag_icon.visible = true
	_drag_icon.global_position = get_viewport().get_mouse_position() - _drag_icon_offset
	_refresh_all_slots()


func _update_drag_icon() -> void:
	if _drag_item == null:
		return
	# 清除舊的格子預覽（先移除再釋放，避免旋轉時新舊同時閃現）
	var old_children := _drag_icon.get_children()
	for child in old_children:
		_drag_icon.remove_child(child)
		child.queue_free()

	var def := _drag_item.get_definition()
	var color_array: Array = def.get("icon_color", [0.5, 0.5, 0.5])
	var item_color := Color(color_array[0], color_array[1], color_array[2], 0.7)
	var shape: Array = _drag_item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cell_size := SLOT_SIZE * 0.8
	var gap := SLOT_GAP * 0.8

	_drag_icon.size = Vector2(cols * cell_size + (cols - 1) * gap, rows * cell_size + (rows - 1) * gap)

	# 為每個佔用格建立獨立的 ColorRect
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

	# Dropped outside panel → remove from inventory
	if target_slot < 0:
		_inventory.remove_item(item)
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
	_drag_icon.visible = false
	_tooltip.visible = false
	_refresh_all_slots()


func _try_move(item: ItemInstance, target_slot: int, old_center: int, old_orientation: int, new_orientation: int) -> void:
	# item 已在 _end_drag 中移除，orientation 已設為 new_orientation
	if _inventory.place_at_anchor(item, target_slot, _drag_anchor):
		return
	# Anchor 放置失敗 — auto-find
	if _inventory.add_item(item) >= 0:
		return
	# Auto-find 也失敗 — 退回原位
	item.orientation = old_orientation
	_inventory.place_at(item, old_center)


func _try_swap(drag_item: ItemInstance, other_item: ItemInstance, target_slot: int, drag_old_center: int, drag_old_orientation: int, drag_new_orientation: int) -> void:
	var other_old_center: int = other_item.center_slot
	var other_old_orientation: int = other_item.orientation

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
	var cx: int = item.center_slot % _inventory.width
	var cy: int = item.center_slot / _inventory.width
	var start_x: int = cx - cols / 2
	var start_y: int = cy - rows / 2
	var click_x: int = clicked_slot % _inventory.width
	var click_y: int = clicked_slot / _inventory.width
	return Vector2i(click_x - start_x, click_y - start_y)
