class_name DungeonMap
extends CanvasLayer

## 地牢地圖系統
## 提供左上角小地圖 (3×3) 和全螢幕大地圖 (M 鍵切換)。
## 追蹤已探索房間、可見未探索房間 (相鄰已探索)、連接通道。

const MINIMAP_CELL_SIZE: float = 56.0
const FULLMAP_CELL_SIZE: float = 60.0
const MINIMAP_MARGIN: float = 16.0
const MINIMAP_SIZE: float = 180.0

var _rooms: Array  # Array[DungeonGenerator.RoomData] — reference to generator rooms
var _room_map: Dictionary  # Vector2i → RoomData
var _explored: Dictionary  # Vector2i → bool
var _current_pos: Vector2i = Vector2i.ZERO
var _full_map_open: bool = false

# UI nodes
var _minimap_panel: Panel
var _minimap: Control
var _full_map_overlay: ColorRect
var _full_map_bg: Panel
var _full_map: Control


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暫停時仍需接收輸入以關閉大地圖

	# ── Minimap panel ──
	_minimap_panel = Panel.new()
	_minimap_panel.name = "MinimapPanel"
	_minimap_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_minimap_panel.offset_left = MINIMAP_MARGIN
	_minimap_panel.offset_top = MINIMAP_MARGIN
	_minimap_panel.offset_right = MINIMAP_MARGIN + MINIMAP_SIZE
	_minimap_panel.offset_bottom = MINIMAP_MARGIN + MINIMAP_SIZE
	# Semi-transparent dark background via stylebox
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	panel_style.border_color = Color(0.4, 0.4, 0.4, 0.8)
	panel_style.border_width_bottom = 1
	panel_style.border_width_top = 1
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	_minimap_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_minimap_panel)

	_minimap = Control.new()
	_minimap.name = "Minimap"
	_minimap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap.clip_contents = true
	_minimap.draw.connect(_on_minimap_draw)
	_minimap_panel.add_child(_minimap)

	# ── Full map overlay ──
	_full_map_overlay = ColorRect.new()
	_full_map_overlay.name = "FullMapOverlay"
	_full_map_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_map_overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	_full_map_overlay.visible = false
	add_child(_full_map_overlay)

	# ── Full map background panel (center 70%) ──
	_full_map_bg = Panel.new()
	_full_map_bg.name = "FullMapBg"
	_full_map_bg.set_anchors_preset(Control.PRESET_CENTER)
	_full_map_bg.anchor_left = 0.15
	_full_map_bg.anchor_top = 0.15
	_full_map_bg.anchor_right = 0.85
	_full_map_bg.anchor_bottom = 0.85
	_full_map_bg.offset_left = 0.0
	_full_map_bg.offset_top = 0.0
	_full_map_bg.offset_right = 0.0
	_full_map_bg.offset_bottom = 0.0
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.08, 0.9)
	bg_style.border_color = Color(0.5, 0.5, 0.5, 0.8)
	bg_style.border_width_bottom = 2
	bg_style.border_width_top = 2
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	_full_map_bg.add_theme_stylebox_override("panel", bg_style)
	_full_map_bg.visible = false
	add_child(_full_map_bg)

	_full_map = Control.new()
	_full_map.name = "FullMap"
	_full_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_map.clip_contents = true
	_full_map.draw.connect(_on_full_map_draw)
	_full_map_bg.add_child(_full_map)


func _process(_delta: float) -> void:
	_minimap.queue_redraw()
	_full_map.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		toggle_full_map()
		get_viewport().set_input_as_handled()


# ── Public API ──

func setup(p_rooms: Array, p_room_map: Dictionary, start_pos: Vector2i) -> void:
	_rooms = p_rooms
	_room_map = p_room_map
	_explored.clear()
	_current_pos = start_pos
	mark_explored(start_pos)


func mark_explored(pos: Vector2i) -> void:
	_explored[pos] = true
	_minimap.queue_redraw()
	_full_map.queue_redraw()


func update_current_pos(pos: Vector2i) -> void:
	_current_pos = pos
	_minimap.queue_redraw()
	_full_map.queue_redraw()


func toggle_full_map() -> void:
	_full_map_open = not _full_map_open
	_full_map_overlay.visible = _full_map_open
	_full_map_bg.visible = _full_map_open
	get_tree().paused = _full_map_open


# ── Visibility helpers ──

func _is_explored(pos: Vector2i) -> bool:
	return pos in _explored


func _is_visible_unexplored(pos: Vector2i) -> bool:
	if _is_explored(pos):
		return false
	if pos not in _room_map:
		return false
	var room_data: DungeonGenerator.RoomData = _room_map[pos]
	for dir in room_data.connections:
		var neighbor_pos: Vector2i = pos + DungeonGenerator.DIRS[dir]
		if _is_explored(neighbor_pos):
			return true
	return false


func _is_room_visible(pos: Vector2i) -> bool:
	return _is_explored(pos) or _is_visible_unexplored(pos)


# ── Draw callbacks ──

func _on_minimap_draw() -> void:
	_draw_map(_minimap, MINIMAP_CELL_SIZE, _current_pos, false)


func _on_full_map_draw() -> void:
	_draw_map(_full_map, FULLMAP_CELL_SIZE, Vector2i.ZERO, true)


# ── Drawing ──

func _draw_map(control: Control, cell_size: float, viewport_center: Vector2i, show_all: bool) -> void:
	var control_size: Vector2 = control.size
	if control_size.x <= 0.0 or control_size.y <= 0.0:
		return

	var center_offset: Vector2 = control_size / 2.0

	# Compute auto-center for full map
	if show_all:
		viewport_center = _compute_fullmap_center()

	# ── Layout parameters ──
	# Grid spacing = cell_size (one cell per grid unit)
	# Room drawn size = cell_size * 0.6 (leaving 40% gap for passages)
	# Passage fills the gap between adjacent rooms
	var room_ratio := 0.6
	var room_draw_size: float = cell_size * room_ratio
	var half_room := room_draw_size * 0.5
	var gap: float = cell_size * (1.0 - room_ratio)  # gap between room edges

	# a. Draw rooms
	for room: DungeonGenerator.RoomData in _rooms:
		var gpos: Vector2i = room.grid_pos

		# Skip hidden rooms
		if not _is_room_visible(gpos):
			continue

		# Clip to 3×3 for minimap
		if not show_all:
			var diff: Vector2i = gpos - viewport_center
			if abs(diff.x) > 1 or abs(diff.y) > 1:
				continue

		var pixel_pos: Vector2 = (Vector2(gpos) - Vector2(viewport_center)) * cell_size + center_offset
		var cell_rect := Rect2(pixel_pos.x - half_room, pixel_pos.y - half_room, room_draw_size, room_draw_size)

		# Room fill color
		if _is_explored(gpos):
			var room_color: Color = DungeonRoom.TYPE_COLORS.get(room.room_type, Color(0.2, 0.2, 0.2, 1))
			control.draw_rect(cell_rect, room_color)
		else:
			control.draw_rect(cell_rect, Color(0.35, 0.35, 0.35, 1))

		# Room border
		control.draw_rect(cell_rect, Color(0.6, 0.6, 0.6, 0.8), false, 1.0)

		# Room label text
		var font: Font = control.get_theme_default_font()
		var font_size: int = int(max(cell_size * 0.25, 6))
		var label: String
		var label_color: Color

		if _is_explored(gpos):
			label = DungeonRoom.TYPE_LABELS.get(room.room_type, "???")
			label_color = Color(0.9, 0.9, 0.9, 0.9)
		else:
			label = "???"
			label_color = Color(0.7, 0.7, 0.7, 0.9)

		var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		control.draw_string(font, pixel_pos - Vector2(label_size.x * 0.5, -font_size * 0.2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)

		# Current room: red dot (label already drawn above, no duplicate)
		if gpos == _current_pos:
			control.draw_circle(pixel_pos, cell_size * 0.12, Color(1.0, 0.2, 0.2, 1.0))

	# b. Draw connections (passages) from explored rooms
	for room: DungeonGenerator.RoomData in _rooms:
		if not _is_explored(room.grid_pos):
			continue
		for dir in room.connections:
			var neighbor_pos: Vector2i = room.grid_pos + DungeonGenerator.DIRS[dir]
			if neighbor_pos not in _room_map:
				continue
			# Only draw if at least one side is explored (current room is explored, so always true)
			if not _is_room_visible(neighbor_pos):
				continue

			var room_pixel: Vector2 = (Vector2(room.grid_pos) - Vector2(viewport_center)) * cell_size + center_offset
			var neighbor_pixel: Vector2 = (Vector2(neighbor_pos) - Vector2(viewport_center)) * cell_size + center_offset

			# Clip check for minimap
			if not show_all:
				var diff_r: Vector2i = room.grid_pos - viewport_center
				var diff_n: Vector2i = neighbor_pos - viewport_center
				if abs(diff_r.x) > 1 or abs(diff_r.y) > 1:
					continue
				if abs(diff_n.x) > 1 or abs(diff_n.y) > 1:
					continue

			# Draw passage filling the gap between room edges
			var passage_center: Vector2 = (room_pixel + neighbor_pixel) * 0.5
			var passage_rect: Rect2
			var passage_width: float = room_draw_size * 0.35  # passage thickness ≈ room width

			if dir == DungeonGenerator.DIR_UP or dir == DungeonGenerator.DIR_DOWN:
				# Vertical passage — fills the gap (length = gap between room edges)
				passage_rect = Rect2(
					passage_center.x - passage_width * 0.5,
					passage_center.y - gap * 0.5,
					passage_width,
					gap
				)
			else:
				# Horizontal passage
				passage_rect = Rect2(
					passage_center.x - gap * 0.5,
					passage_center.y - passage_width * 0.5,
					gap,
					passage_width
				)

			control.draw_rect(passage_rect, Color(0.7, 0.7, 0.7, 0.7))


func _compute_fullmap_center() -> Vector2i:
	if _rooms.is_empty():
		return Vector2i.ZERO
	var min_x: int = 999999
	var min_y: int = 999999
	var max_x: int = -999999
	var max_y: int = -999999
	for room: DungeonGenerator.RoomData in _rooms:
		if not _is_room_visible(room.grid_pos):
			continue
		min_x = mini(min_x, room.grid_pos.x)
		min_y = mini(min_y, room.grid_pos.y)
		max_x = maxi(max_x, room.grid_pos.x)
		max_y = maxi(max_y, room.grid_pos.y)
	return Vector2i((min_x + max_x) >> 1, (min_y + max_y) >> 1)
