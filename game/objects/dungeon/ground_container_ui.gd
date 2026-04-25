class_name GroundContainerUI
extends CanvasLayer

signal closed

const SLOT_SIZE := 96.0
const SLOT_PADDING := 4.0
const SLOT_GAP := 3.0
const GROUND_VISIBLE_ROWS := 4
const GROUND_MAX_ROWS := 20
const INTERACT_RANGE := 200.0

enum DragSource { GROUND, PLAYER }

var _ground_container: InvContainer
var _ground_room: Node2D = null
var _player_inventory: PlayerInventory
var _player: CharacterBody2D
var _trigger_world_pos: Vector2 = Vector2.ZERO
var _is_open: bool = false

var _ground_slot_controls: Array = []
var _ground_item_layer: Control
var _ground_content: Control
var _ground_scroll: ScrollContainer
var _ground_label: Label

var _player_slot_controls: Array = []
var _player_item_layer: Control
var _player_content: Control
var _player_label: Label

var _dragging: bool = false
var _drag_item: ItemInstance = null
var _drag_source: int = -1
var _drag_original_center: int = -1
var _drag_original_orientation: int = 0
var _drag_anchor: Vector2i = Vector2i.ZERO
var _drag_icon_offset: Vector2 = Vector2.ZERO
var _hover_slot: int = -1
var _hover_panel: int = -1

var _main_panel: Panel
var _bg_overlay: ColorRect
var _tooltip: Label
var _drag_icon: Control
var _title: Label
var _separator: ColorRect


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS

	_bg_overlay = ColorRect.new()
	_bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_overlay.color = Color(0, 0, 0, 0.5)
	_bg_overlay.visible = false
	add_child(_bg_overlay)

	_main_panel = Panel.new()
	_main_panel.set_anchors_preset(Control.PRESET_CENTER)
	_main_panel.visible = false
	add_child(_main_panel)

	_title = Label.new()
	_title.text = "物品撿拾"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 18)
	_main_panel.add_child(_title)

	_ground_label = Label.new()
	_ground_label.text = "地面物品"
	_ground_label.add_theme_font_size_override("font_size", 14)
	_ground_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_panel.add_child(_ground_label)

	_ground_scroll = ScrollContainer.new()
	_ground_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ground_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_main_panel.add_child(_ground_scroll)

	_ground_content = Control.new()
	_ground_content.name = "GroundContent"
	_ground_scroll.add_child(_ground_content)

	_separator = ColorRect.new()
	_separator.color = Color(0.4, 0.4, 0.45, 0.9)
	_main_panel.add_child(_separator)

	_player_label = Label.new()
	_player_label.text = "背包"
	_player_label.add_theme_font_size_override("font_size", 14)
	_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_panel.add_child(_player_label)

	_player_content = Control.new()
	_player_content.name = "PlayerContent"
	_main_panel.add_child(_player_content)

	_tooltip = Label.new()
	_tooltip.add_theme_font_size_override("font_size", 13)
	_tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tooltip.add_theme_constant_override("outline_size", 2)
	_tooltip.visible = false
	_tooltip.z_index = 5
	add_child(_tooltip)

	_drag_icon = Control.new()
	_drag_icon.z_index = 100
	_drag_icon.visible = false
	add_child(_drag_icon)


func setup(ground_container: InvContainer, player_inventory: PlayerInventory, player: CharacterBody2D, trigger_world_pos: Vector2, ground_room: Node2D = null) -> void:
	if _ground_container != null and _ground_container.contents_changed.is_connected(_on_ground_contents_changed):
		_ground_container.contents_changed.disconnect(_on_ground_contents_changed)
	if _player_inventory != null and _player_inventory.contents_changed.is_connected(_on_player_contents_changed):
		_player_inventory.contents_changed.disconnect(_on_player_contents_changed)

	_ground_container = ground_container
	_ground_room = ground_room
	_player_inventory = player_inventory
	_player = player
	_trigger_world_pos = trigger_world_pos

	if _ground_container != null:
		_ground_container.contents_changed.connect(_on_ground_contents_changed)
	if _player_inventory != null:
		_player_inventory.contents_changed.connect(_on_player_contents_changed)

	_rebuild_ground_panel()
	_rebuild_player_panel()
	_update_main_panel_size()


func open() -> void:
	if _ground_container == null or _player_inventory == null:
		return
	_is_open = true
	_bg_overlay.visible = true
	_main_panel.visible = true
	_tooltip.visible = false
	_ground_scroll.scroll_vertical = 0
	_refresh_all()


func close() -> void:
	if not _is_open:
		return
	if _dragging:
		_cancel_drag()
	_is_open = false
	_bg_overlay.visible = false
	_main_panel.visible = false
	_tooltip.visible = false
	_hover_slot = -1
	_hover_panel = -1
	closed.emit()


func _slot_col(idx: int, container_width: int) -> int:
	return idx % container_width


func _slot_row(idx: int, container_width: int) -> int:
	return floori(idx / float(container_width))


func _create_slot_panel() -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(SLOT_PADDING)
	slot.add_theme_stylebox_override("panel", style)
	return slot


func _clear_node_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _rebuild_ground_panel() -> void:
	if _ground_container == null:
		return
	_clear_node_children(_ground_content)
	_ground_slot_controls.clear()

	var grid_w := _ground_container.width * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var grid_h := _ground_container.height * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	_ground_content.custom_minimum_size = Vector2(grid_w, grid_h)
	_ground_content.size = Vector2(grid_w, grid_h)

	for i in _ground_container.get_slot_count():
		var slot := _create_slot_panel()
		var x := _slot_col(i, _ground_container.width)
		var y := _slot_row(i, _ground_container.width)
		slot.position = Vector2(x * (SLOT_SIZE + SLOT_GAP), y * (SLOT_SIZE + SLOT_GAP))
		slot.name = "GroundSlot_%d" % i
		_ground_content.add_child(slot)
		_ground_slot_controls.append(slot)

	_ground_item_layer = Control.new()
	_ground_item_layer.name = "GroundItemLayer"
	_ground_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground_item_layer.size = Vector2(grid_w, grid_h)
	_ground_content.add_child(_ground_item_layer)

	_update_main_panel_size()
	_refresh_ground_items()


func _rebuild_player_panel() -> void:
	if _player_inventory == null:
		return
	_clear_node_children(_player_content)
	_player_slot_controls.clear()

	var grid_w := _player_inventory.width * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var grid_h := _player_inventory.height * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	_player_content.custom_minimum_size = Vector2(grid_w, grid_h)
	_player_content.size = Vector2(grid_w, grid_h)

	for i in _player_inventory.get_slot_count():
		var slot := _create_slot_panel()
		var x := _slot_col(i, _player_inventory.width)
		var y := _slot_row(i, _player_inventory.width)
		slot.position = Vector2(x * (SLOT_SIZE + SLOT_GAP), y * (SLOT_SIZE + SLOT_GAP))
		slot.name = "PlayerSlot_%d" % i
		_player_content.add_child(slot)
		_player_slot_controls.append(slot)

	_player_item_layer = Control.new()
	_player_item_layer.name = "PlayerItemLayer"
	_player_item_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_item_layer.size = Vector2(grid_w, grid_h)
	_player_content.add_child(_player_item_layer)

	_update_main_panel_size()
	_refresh_player_items()


func _update_main_panel_size() -> void:
	if _ground_container == null or _player_inventory == null:
		return

	var ground_w := _ground_container.width * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var ground_h_visible := GROUND_VISIBLE_ROWS * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var player_w := _player_inventory.width * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var player_h := _player_inventory.height * (SLOT_SIZE + SLOT_GAP) + SLOT_GAP
	var section_top := 34.0
	var label_h := 24.0
	var section_gap := 18.0
	var panel_padding := 18.0
	var separator_w := 2.0
	var content_y := section_top + label_h + 8.0
	var panel_w := panel_padding * 2.0 + ground_w + section_gap + separator_w + section_gap + player_w
	var panel_h := content_y + maxf(ground_h_visible, player_h) + 18.0

	_main_panel.offset_left = -panel_w * 0.5
	_main_panel.offset_top = -panel_h * 0.5
	_main_panel.offset_right = panel_w * 0.5
	_main_panel.offset_bottom = panel_h * 0.5

	_title.offset_left = 0.0
	_title.offset_top = 6.0
	_title.offset_right = panel_w
	_title.offset_bottom = 28.0

	_ground_label.offset_left = panel_padding
	_ground_label.offset_top = section_top
	_ground_label.offset_right = panel_padding + ground_w
	_ground_label.offset_bottom = section_top + label_h

	_ground_scroll.position = Vector2(panel_padding, content_y)
	_ground_scroll.size = Vector2(ground_w, ground_h_visible)

	_separator.position = Vector2(panel_padding + ground_w + section_gap, section_top)
	_separator.size = Vector2(separator_w, panel_h - section_top - 18.0)

	var player_x := panel_padding + ground_w + section_gap + separator_w + section_gap
	_player_label.offset_left = player_x
	_player_label.offset_top = section_top
	_player_label.offset_right = player_x + player_w
	_player_label.offset_bottom = section_top + label_h

	_player_content.position = Vector2(player_x, content_y)
	_player_content.size = Vector2(player_w, player_h)


func _on_ground_contents_changed() -> void:
	if _ground_slot_controls.size() != _ground_container.get_slot_count():
		_rebuild_ground_panel()
	else:
		_refresh_ground_items()


func _on_player_contents_changed() -> void:
	if _player_slot_controls.size() != _player_inventory.get_slot_count():
		_rebuild_player_panel()
	else:
		_refresh_player_items()


func _refresh_all() -> void:
	_refresh_ground_items()
	_refresh_player_items()


func _refresh_ground_items() -> void:
	if _ground_item_layer == null or _ground_container == null:
		return
	_clear_node_children(_ground_item_layer)
	for item: ItemInstance in _ground_container.get_all_items():
		if _dragging and _drag_source == DragSource.GROUND and item == _drag_item:
			continue
		_add_item_visual(item, _ground_item_layer, _ground_container.width, false)
	if _dragging and _drag_source == DragSource.GROUND and _drag_item != null:
		_add_ghost_visual(DragSource.GROUND)
	if _dragging and _hover_panel == DragSource.GROUND and _hover_slot >= 0:
		_add_preview_visual(DragSource.GROUND)


func _refresh_player_items() -> void:
	if _player_item_layer == null or _player_inventory == null:
		return
	_clear_node_children(_player_item_layer)
	for item: ItemInstance in _player_inventory.get_all_items():
		if _dragging and _drag_source == DragSource.PLAYER and item == _drag_item:
			continue
		_add_item_visual(item, _player_item_layer, _player_inventory.width, true)
	if _dragging and _drag_source == DragSource.PLAYER and _drag_item != null:
		_add_ghost_visual(DragSource.PLAYER)
	if _dragging and _hover_panel == DragSource.PLAYER and _hover_slot >= 0:
		_add_preview_visual(DragSource.PLAYER)


func _add_item_visual(item: ItemInstance, item_layer: Control, container_width: int, show_equipped: bool) -> void:
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _slot_col(item.center_slot, container_width)
	var cy: int = _slot_row(item.center_slot, container_width)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)

	var pos_x: float = start_x * (SLOT_SIZE + SLOT_GAP)
	var pos_y: float = start_y * (SLOT_SIZE + SLOT_GAP)
	var size_x: float = cols * SLOT_SIZE + (cols - 1) * SLOT_GAP
	var size_y: float = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP

	if show_equipped and item.equipped:
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
		item_layer.add_child(highlight)

	var tex: ImageTexture = ItemDatabase.get_item_texture(item.item_id, item.orientation)
	if tex != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = tex
		icon_rect.position = Vector2(pos_x, pos_y)
		icon_rect.size = Vector2(size_x, size_y)
		icon_rect.stretch_mode = TextureRect.STRETCH_SCALE
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_layer.add_child(icon_rect)
	else:
		var def := item.get_definition()
		var color_array: Array = def.get("icon_color", [0.5, 0.5, 0.5])
		var cr := ColorRect.new()
		cr.color = Color(color_array[0], color_array[1], color_array[2])
		cr.position = Vector2(pos_x, pos_y)
		cr.size = Vector2(size_x, size_y)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_layer.add_child(cr)


func _add_ghost_visual(target_panel: int) -> void:
	var item_layer := _get_item_layer(target_panel)
	var container_width := _get_container_width(target_panel)
	var saved_ori: int = _drag_item.orientation
	_drag_item.orientation = _drag_original_orientation
	var shape: Array = _drag_item.get_rotated_shape()
	_drag_item.orientation = saved_ori

	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _slot_col(_drag_original_center, container_width)
	var cy: int = _slot_row(_drag_original_center, container_width)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)
	var ghost_color := Color(0.8, 0.8, 0.8, 0.3)

	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var sx: int = start_x + x
				var sy: int = start_y + y
				var cr := ColorRect.new()
				cr.color = ghost_color
				cr.position = Vector2(sx * (SLOT_SIZE + SLOT_GAP), sy * (SLOT_SIZE + SLOT_GAP))
				cr.size = Vector2(SLOT_SIZE, SLOT_SIZE)
				cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				item_layer.add_child(cr)


func _add_preview_visual(target_panel: int) -> void:
	var item_layer := _get_item_layer(target_panel)
	var container := _get_container(target_panel)
	var container_width := _get_container_width(target_panel)
	var shape: Array = _drag_item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var tx: int = _slot_col(_hover_slot, container_width)
	var ty: int = _slot_row(_hover_slot, container_width)
	var start_x: int = tx - _drag_anchor.x
	var start_y: int = ty - _drag_anchor.y
	var ignore_item: ItemInstance = _drag_item if target_panel == _drag_source else null
	var valid: bool = container.can_place_at_anchor(_drag_item, _hover_slot, _drag_anchor, ignore_item)
	var preview_color := Color(0.2, 0.8, 0.3, 0.35) if valid else Color(0.8, 0.2, 0.2, 0.35)

	for y in rows:
		var row: Array = shape[y] as Array
		for x in cols:
			if row[x] == 1:
				var sx: int = start_x + x
				var sy: int = start_y + y
				if sx < 0 or sy < 0 or sx >= container.width or sy >= container.height:
					continue
				var cr := ColorRect.new()
				cr.color = preview_color
				cr.position = Vector2(sx * (SLOT_SIZE + SLOT_GAP), sy * (SLOT_SIZE + SLOT_GAP))
				cr.size = Vector2(SLOT_SIZE, SLOT_SIZE)
				cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				item_layer.add_child(cr)


func _process(_delta: float) -> void:
	if not _is_open:
		return
	if is_instance_valid(_player) and _player.global_position.distance_to(_trigger_world_pos) > INTERACT_RANGE:
		close()
		return
	if _dragging and _drag_icon.visible:
		_drag_icon.global_position = get_viewport().get_mouse_position() - _drag_icon_offset
		var info := _get_slot_info_at_position(get_viewport().get_mouse_position())
		var new_panel: int = info["panel"]
		var new_slot: int = info["slot"]
		if new_panel != _hover_panel or new_slot != _hover_slot:
			_hover_panel = new_panel
			_hover_slot = new_slot
			_refresh_all()


func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
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
	var info := _get_slot_info_at_position(event.global_position)
	if info["panel"] < 0 or info["slot"] < 0:
		return
	var container := _get_container(info["panel"])
	var item: ItemInstance = container.find_item_at(info["slot"])
	if item != null:
		var anchor := _compute_anchor(info["slot"], item, _get_container_width(info["panel"]))
		_start_drag(item, info["panel"], anchor)


func _on_left_release(event: InputEventMouseButton) -> void:
	if not _dragging:
		return
	var info := _get_slot_info_at_position(event.global_position)
	_end_drag(info["panel"], info["slot"])


func _on_right_click(event: InputEventMouseButton) -> void:
	var info := _get_slot_info_at_position(event.global_position)
	if info["panel"] != DragSource.PLAYER or info["slot"] < 0:
		return
	var item: ItemInstance = _player_inventory.find_item_at(info["slot"])
	if item == null:
		return
	if item.is_consumable():
		_player_inventory.use_consumable(info["slot"])
	else:
		_player_inventory.toggle_equip(info["slot"])


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _dragging:
		_tooltip.visible = false
		return
	var info := _get_slot_info_at_position(event.global_position)
	if info["panel"] >= 0 and info["slot"] >= 0:
		var container := _get_container(info["panel"])
		var item: ItemInstance = container.find_item_at(info["slot"])
		if item != null:
			var item_name := item.get_display_name()
			var def := item.get_definition()
			var desc: String = def.get("description", "")
			_tooltip.text = item_name + "\n" + desc if desc != "" else item_name
			_tooltip.visible = true
			_tooltip.global_position = event.global_position + Vector2(15.0, 15.0)
			return
	_tooltip.visible = false


func _handle_rotation() -> void:
	if not _dragging or _drag_item == null:
		return
	if _drag_item.can_rotate():
		var old_shape: Array = _drag_item.get_rotated_shape()
		var old_rows: int = old_shape.size()
		_drag_anchor = Vector2i(old_rows - 1 - _drag_anchor.y, _drag_anchor.x)
		_drag_item.orientation = (_drag_item.orientation + 1) % 4
		_update_drag_icon()
		_refresh_all()


func _start_drag(item: ItemInstance, source: int, anchor: Vector2i) -> void:
	_dragging = true
	_drag_item = item
	_drag_source = source
	_drag_original_center = item.center_slot
	_drag_original_orientation = item.orientation
	_drag_anchor = anchor
	_hover_panel = source
	_hover_slot = item.center_slot
	_update_drag_icon()
	_drag_icon.visible = true
	_drag_icon.global_position = get_viewport().get_mouse_position() - _drag_icon_offset
	_refresh_all()


func _update_drag_icon() -> void:
	if _drag_item == null:
		return
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

	_drag_icon_offset = Vector2(
		_drag_anchor.x * (cell_size + gap) + cell_size * 0.5,
		_drag_anchor.y * (cell_size + gap) + cell_size * 0.5
	)


func _end_drag(target_panel: int, target_slot: int) -> void:
	var item := _drag_item
	if item == null:
		_clear_drag()
		return
	if target_panel < 0 or target_slot < 0:
		_clear_drag()
		return
	if target_panel == _drag_source:
		_complete_same_container_drag(target_panel, target_slot)
	else:
		_complete_cross_container_drag(target_panel, target_slot)
	_clear_drag()


func _complete_same_container_drag(target_panel: int, target_slot: int) -> void:
	var container := _get_container(target_panel)
	var item := _drag_item
	var old_center: int = _drag_original_center
	var old_orientation: int = _drag_original_orientation
	var new_orientation: int = item.orientation
	item.orientation = old_orientation

	var target_item: ItemInstance = container.find_item_at(target_slot)
	container.remove_item(item)
	item.orientation = new_orientation

	if target_item == item or target_item == null:
		if not container.place_at_anchor(item, target_slot, _drag_anchor):
			item.orientation = old_orientation
			if not container.place_at(item, old_center):
				container.add_item(item)
		return

	_try_swap_in_container(container, item, target_item, target_slot, old_center, old_orientation, new_orientation)


func _complete_cross_container_drag(target_panel: int, target_slot: int) -> void:
	var source_container := _get_container(_drag_source)
	var target_container := _get_container(target_panel)
	var item := _drag_item
	var old_center: int = _drag_original_center
	var old_orientation: int = _drag_original_orientation
	var new_orientation: int = item.orientation
	var drag_hotbar_indices: Array[int] = []
	if _drag_source == DragSource.PLAYER:
		drag_hotbar_indices = _get_bound_hotbar_indices(item)

	item.orientation = old_orientation
	var target_item: ItemInstance = target_container.find_item_at(target_slot)
	source_container.remove_item(item)
	item.orientation = new_orientation

	if target_item == null:
		if _place_in_target_container(target_container, item, target_panel, target_slot):
			if _drag_source == DragSource.PLAYER:
				_clear_hotbar_binding_indices(drag_hotbar_indices)
			return
		item.orientation = old_orientation
		source_container.place_at(item, old_center)
		return

	var other_hotbar_indices: Array[int] = []
	if target_panel == DragSource.PLAYER:
		other_hotbar_indices = _get_bound_hotbar_indices(target_item)
	_try_swap_between_containers(
		source_container,
		target_container,
		target_panel,
		item,
		target_item,
		target_slot,
		old_center,
		old_orientation,
		drag_hotbar_indices,
		other_hotbar_indices,
	)


func _place_in_target_container(target_container: InvContainer, item: ItemInstance, target_panel: int, target_slot: int) -> bool:
	if target_panel == DragSource.GROUND:
		_stamp_ground_drop_position(item)
	if target_container.place_at_anchor(item, target_slot, _drag_anchor):
		return true
	if target_panel == DragSource.GROUND:
		return _add_to_ground_with_resize(item) >= 0
	return target_container.add_item(item) >= 0


func _add_to_ground_with_resize(item: ItemInstance) -> int:
	if _ground_container.add_item(item) >= 0:
		return item.center_slot
	while _ground_container.height < GROUND_MAX_ROWS:
		_ground_container.resize(_ground_container.width, _ground_container.height + 2)
		if _ground_container.add_item(item) >= 0:
			return item.center_slot
	return -1


func _try_swap_in_container(container: InvContainer, drag_item: ItemInstance, other_item: ItemInstance, target_slot: int, drag_old_center: int, drag_old_orientation: int, _drag_new_orientation: int) -> void:
	var other_old_center: int = other_item.center_slot
	container.remove_item(other_item)
	if container.place_at_anchor(drag_item, target_slot, _drag_anchor):
		if container.place_at(other_item, drag_old_center):
			return
		if container.add_item(other_item) >= 0:
			return
		container.remove_item(drag_item)
		drag_item.orientation = drag_old_orientation
		container.place_at(drag_item, drag_old_center)
		container.place_at(other_item, other_old_center)
	else:
		if container.add_item(drag_item) >= 0:
			if container.place_at(other_item, other_old_center):
				return
			container.add_item(other_item)
		else:
			drag_item.orientation = drag_old_orientation
			container.place_at(drag_item, drag_old_center)
			container.place_at(other_item, other_old_center)


func _try_swap_between_containers(source_container: InvContainer, target_container: InvContainer, target_panel: int, drag_item: ItemInstance, other_item: ItemInstance, target_slot: int, drag_old_center: int, drag_old_orientation: int, drag_hotbar_indices: Array[int], other_hotbar_indices: Array[int]) -> void:
	var other_old_center: int = other_item.center_slot
	var other_old_orientation: int = other_item.orientation
	target_container.remove_item(other_item)

	if _place_in_target_container(target_container, drag_item, target_panel, target_slot):
		if _drag_source == DragSource.GROUND:
			_stamp_ground_drop_position(other_item)
		if source_container.place_at(other_item, drag_old_center):
			_clear_hotbar_binding_indices(drag_hotbar_indices)
			_clear_hotbar_binding_indices(other_hotbar_indices)
			return
		var other_placed: bool = false
		if _drag_source == DragSource.GROUND:
			other_placed = _add_to_ground_with_resize(other_item) >= 0
		else:
			other_placed = source_container.add_item(other_item) >= 0
		if other_placed:
			_clear_hotbar_binding_indices(drag_hotbar_indices)
			_clear_hotbar_binding_indices(other_hotbar_indices)
			return
		target_container.remove_item(drag_item)
		drag_item.orientation = drag_old_orientation
		source_container.place_at(drag_item, drag_old_center)
		other_item.orientation = other_old_orientation
		target_container.place_at(other_item, other_old_center)
		return

	other_item.orientation = other_old_orientation
	target_container.place_at(other_item, other_old_center)
	drag_item.orientation = drag_old_orientation
	source_container.place_at(drag_item, drag_old_center)


func _cancel_drag() -> void:
	if _drag_item != null:
		_drag_item.orientation = _drag_original_orientation
	_clear_drag()


func _clear_drag() -> void:
	_dragging = false
	_drag_item = null
	_drag_source = -1
	_drag_original_center = -1
	_drag_original_orientation = 0
	_drag_anchor = Vector2i.ZERO
	_hover_slot = -1
	_hover_panel = -1
	var old_children := _drag_icon.get_children()
	for child in old_children:
		_drag_icon.remove_child(child)
		child.queue_free()
	_drag_icon.visible = false
	_tooltip.visible = false
	_refresh_all()


func _get_bound_hotbar_indices(item: ItemInstance) -> Array[int]:
	var result: Array[int] = []
	if _player_inventory == null:
		return result
	for i in _player_inventory.hotbar.size():
		if _player_inventory.hotbar[i] == item.center_slot:
			result.append(i)
	return result


func _clear_hotbar_binding_indices(indices: Array[int]) -> void:
	if _player_inventory == null:
		return
	for idx: int in indices:
		if idx >= 0 and idx < _player_inventory.hotbar.size():
			_player_inventory.hotbar[idx] = -1


func _stamp_ground_drop_position(item: ItemInstance) -> void:
	if _ground_room == null or not is_instance_valid(_player):
		return
	var local_pos: Vector2 = _ground_room.to_local(_player.global_position)
	item.metadata["drop_pos_x"] = local_pos.x
	item.metadata["drop_pos_y"] = local_pos.y


func _get_slot_info_at_position(global_pos: Vector2) -> Dictionary:
	var ground_slot := _get_slot_at_position(global_pos, _ground_slot_controls)
	if ground_slot >= 0:
		return { "panel": DragSource.GROUND, "slot": ground_slot }
	var player_slot := _get_slot_at_position(global_pos, _player_slot_controls)
	if player_slot >= 0:
		return { "panel": DragSource.PLAYER, "slot": player_slot }
	return { "panel": -1, "slot": -1 }


func _get_slot_at_position(global_pos: Vector2, slot_controls: Array) -> int:
	for i in slot_controls.size():
		var slot: Control = slot_controls[i]
		var rect := Rect2(slot.global_position, slot.size)
		if rect.has_point(global_pos):
			return i
	return -1


func _compute_anchor(clicked_slot: int, item: ItemInstance, container_width: int) -> Vector2i:
	var shape: Array = item.get_rotated_shape()
	var rows: int = shape.size()
	var cols: int = (shape[0] as Array).size()
	var cx: int = _slot_col(item.center_slot, container_width)
	var cy: int = _slot_row(item.center_slot, container_width)
	var start_x: int = cx - (cols >> 1)
	var start_y: int = cy - (rows >> 1)
	var click_x: int = _slot_col(clicked_slot, container_width)
	var click_y: int = _slot_row(clicked_slot, container_width)
	return Vector2i(click_x - start_x, click_y - start_y)


func _get_container(panel: int) -> InvContainer:
	if panel == DragSource.GROUND:
		return _ground_container
	return _player_inventory


func _get_item_layer(panel: int) -> Control:
	if panel == DragSource.GROUND:
		return _ground_item_layer
	return _player_item_layer


func _get_container_width(panel: int) -> int:
	if panel == DragSource.GROUND:
		return _ground_container.width
	return _player_inventory.width
