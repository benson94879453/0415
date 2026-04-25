class_name WallSlot
extends Area2D

@export var slot_index: int = 0
@export var grid_pos: Vector2i = Vector2i.ZERO
@export var target_grid_pos: Vector2i = Vector2i.ZERO
@export var is_blank: bool = true
@export var target_room_type: int = DungeonRoom.RoomType.START

@onready var visual: ColorRect = $Visual
@onready var highlight: ColorRect = $Highlight

func _ready() -> void:
	if not Engine.is_editor_hint():
		if visual:
			visual.color = Color(0.3, 0.3, 0.35, 1.0)
		if highlight:
			highlight.visible = false

func setup(p_slot_index: int, p_grid_pos: Vector2i, p_target_grid_pos: Vector2i, p_is_blank: bool, p_target_room_type: int) -> void:
	slot_index = p_slot_index
	grid_pos = p_grid_pos
	target_grid_pos = p_target_grid_pos
	is_blank = p_is_blank
	target_room_type = p_target_room_type
	
	if visual:
		visual.color = Color(0.3, 0.3, 0.35, 1.0)
	if highlight:
		highlight.visible = false

func set_highlight(enabled: bool) -> void:
	if highlight:
		highlight.visible = enabled
