class_name GroundItemVisual extends Area2D
## Visual representation of a single item dropped on the ground in a dungeon room.
## Created and managed by dungeon.gd; interaction is handled externally.

var item_instance: ItemInstance
var room_ref  #: DungeonRoom (duck-typed, no class_name dependency)


func _ready() -> void:
	add_to_group("ground_items")


## Stores references and builds the visual + collision nodes.
func setup(item: ItemInstance, room) -> void:
	item_instance = item
	room_ref = room
	z_index = 5
	collision_layer = 0
	collision_mask = 1
	monitoring = true

	# --- Collision ---
	var col_shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(40, 40)
	col_shape.shape = rect_shape
	add_child(col_shape)

	# --- Visual (icon or fallback colour block) ---
	var texture: ImageTexture = ItemDatabase.get_item_texture(item_instance.item_id, 0)
	var visual_node: Control

	if texture:
		var tex_rect := TextureRect.new()
		tex_rect.texture = texture
		tex_rect.size = Vector2(24, 24)
		tex_rect.position = Vector2(-12, -12)
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual_node = tex_rect
	else:
		var color_rect := ColorRect.new()
		var icon_color: Array = item_instance.get_definition().get("icon_color", [0.5, 0.5, 0.5])
		color_rect.color = Color(icon_color[0], icon_color[1], icon_color[2])
		color_rect.size = Vector2(24, 24)
		color_rect.position = Vector2(-12, -12)
		visual_node = color_rect

	add_child(visual_node)

	# --- Name label ---
	var label := Label.new()
	label.text = item_instance.get_display_name()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.position = Vector2(-40, 18)
	label.size = Vector2(80, 14)

	# White text with black outline for readability
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)

	add_child(label)


## Static factory — creates, sets up, positions, and returns a new GroundItemVisual.
static func create(item: ItemInstance, room, world_pos: Vector2) -> GroundItemVisual:
	var visual := GroundItemVisual.new()
	visual.setup(item, room)
	visual.position = world_pos
	return visual
