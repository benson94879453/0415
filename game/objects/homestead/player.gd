extends CharacterBody2D

## 家園場景內的簡易玩家角色（俯視角移動）
## 負責追蹤附近可互動物件，按 E 觸發最近的互動。

signal interacted(target: Area2D)

@export var speed: float = 200.0

## 目前在互動範圍內的 Area2D 清單
var _nearby_interactables: Array[Area2D] = []


func _physics_process(_delta: float) -> void:
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"),
	)
	velocity = input_dir.normalized() * speed
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _try_interact() -> void:
	if _nearby_interactables.is_empty():
		return
	var closest: Area2D = null
	var closest_dist: float = INF
	for area in _nearby_interactables:
		var dist := global_position.distance_to(area.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = area
	if closest:
		interacted.emit(closest)


func register_interactable(area: Area2D) -> void:
	if area not in _nearby_interactables:
		_nearby_interactables.append(area)


func unregister_interactable(area: Area2D) -> void:
	_nearby_interactables.erase(area)
