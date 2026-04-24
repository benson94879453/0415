extends CharacterBody2D
class_name CombatPlayer

## 戰鬥場景中的玩家角色（Vampire Survivors 風格自動攻擊）
## 在基礎移動/互動之外，加入：自動攻擊、閃避翻滾、HP系統
##
## 注意：需要在 Input Map 新增 "dodge" 動作並對應 Space 鍵。
## InventoryEvaluator autoload（另行建立）需提供：
##   get_total_stats() -> Dictionary { attack, defense, speed, attack_speed_multiplier, max_hp, max_mp }
##   get_attack_config() -> Dictionary { type, cooldown, range, arc_deg, projectile_speed }

signal interacted(target: Area2D)
signal hp_changed(current: float, maximum: float)
signal player_died

@export var speed: float = 200.0
@export var max_hp: float = 100.0

var current_hp: float = 100.0
var invincible: bool = false

var _attack_cooldown: float = 0.0
var _facing: Vector2 = Vector2(1, 0)
var _is_dodging: bool = false
var _dodge_timer: float = 0.0
var _dodge_duration: float = 0.25
var _dodge_speed: float = 500.0
var _dodge_direction: Vector2 = Vector2.ZERO

var _nearby_interactables: Array[Area2D] = []
var _prompt_label: Label
var _hp_label: Label
var _body_rect: ColorRect


func _ready() -> void:
	current_hp = max_hp
	_add_to_group("player")
	_create_visual()
	_create_interaction_prompt()
	_create_hp_label()


func _create_visual() -> void:
	_body_rect = ColorRect.new()
	_body_rect.name = "PlayerBody"
	_body_rect.size = Vector2(20, 20)
	_body_rect.position = Vector2(-10, -10)
	_body_rect.color = Color.GREEN
	add_child(_body_rect)


func _create_interaction_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.name = "InteractionPrompt"
	_prompt_label.text = "[E] 互動"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.offset_left = -40.0
	_prompt_label.offset_top = -50.0
	_prompt_label.offset_right = 40.0
	_prompt_label.offset_bottom = -30.0
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("outline_size", 2)
	_prompt_label.z_index = 10
	_prompt_label.visible = false
	add_child(_prompt_label)


func _create_hp_label() -> void:
	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.offset_left = -30.0
	_hp_label.offset_top = -65.0
	_hp_label.offset_right = 30.0
	_hp_label.offset_bottom = -50.0
	_hp_label.add_theme_font_size_override("font_size", 12)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hp_label.add_theme_constant_override("outline_size", 2)
	_hp_label.z_index = 10
	_update_hp_label()
	add_child(_hp_label)


func _update_hp_label() -> void:
	if _hp_label:
		_hp_label.text = "%d / %d" % [int(current_hp), int(max_hp)]


func _physics_process(delta: float) -> void:
	if _is_dodging:
		_process_dodge(delta)
	else:
		_process_movement(delta)

	_prompt_label.visible = not _nearby_interactables.is_empty()

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	if _attack_cooldown <= 0.0 and not _is_dodging:
		_try_auto_attack()


func _process_dodge(delta: float) -> void:
	_dodge_timer -= delta
	velocity = _dodge_direction * _dodge_speed
	move_and_slide()
	if _dodge_timer <= 0.0:
		_is_dodging = false
		invincible = false


func _process_movement(_delta: float) -> void:
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"),
	)
	var effective_speed := speed
	if _has_inventory_evaluator():
		var stats: Dictionary = InventoryEvaluator.get_total_stats()
		effective_speed = speed + stats.get("speed", 0.0)
	velocity = input_dir.normalized() * effective_speed
	if input_dir != Vector2.ZERO:
		_facing = input_dir.normalized()
	move_and_slide()


func _try_auto_attack() -> void:
	if not _has_inventory_evaluator():
		return

	var attack_config: Dictionary = InventoryEvaluator.get_attack_config()
	var total_stats: Dictionary = InventoryEvaluator.get_total_stats()
	var attack_type: String = attack_config.get("type", "melee")
	var attack_range: float = attack_config.get("range", 80.0)
	var attack_cooldown: float = attack_config.get("cooldown", 0.5)
	var arc_deg: float = attack_config.get("arc_deg", 90.0)
	var projectile_speed: float = attack_config.get("projectile_speed", 300.0)
	var damage: float = total_stats.get("attack", 5.0)

	var nearest_enemy: Node2D = _find_nearest_enemy(500.0 if attack_type == "ranged" else 300.0)
	if nearest_enemy == null:
		return

	if attack_type == "melee":
		_execute_melee_attack(damage, attack_range, arc_deg)
	else:
		_execute_ranged_attack(nearest_enemy, damage, projectile_speed)

	_attack_cooldown = attack_cooldown / total_stats.get("attack_speed_multiplier", 1.0)


func _find_nearest_enemy(max_range: float) -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	var closest: Node2D = null
	var closest_dist: float = max_range
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	return closest


func _execute_melee_attack(damage: float, attack_range: float, arc_deg: float) -> void:
	var half_arc_rad: float = deg_to_rad(arc_deg * 0.5)
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if not enemy.has_method("take_damage"):
			continue
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist > attack_range:
			continue
		var to_enemy: Vector2 = (enemy.global_position - global_position).normalized()
		if _facing.length_squared() > 0.0 and to_enemy.length_squared() > 0.0:
			var angle: float = _facing.angle_to(to_enemy)
			if abs(angle) > half_arc_rad:
				continue
		enemy.take_damage(damage)


func _execute_ranged_attack(target: Node2D, damage: float, projectile_speed: float) -> void:
	var direction: Vector2 = (target.global_position - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = _facing
	var projectile: CharacterBody2D = _create_projectile()
	projectile.global_position = global_position
	projectile.set("direction", direction)
	projectile.set("speed", projectile_speed)
	projectile.set("damage", damage)
	get_parent().add_child(projectile)


func _create_projectile() -> CharacterBody2D:
	var p := CharacterBody2D.new()
	var script := load("res://game/objects/combat/projectile.gd")
	if script:
		p.set_script(script)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()
		return
	# "dodge" action needs to be added to Input Map (Space key)
	if event.is_action_pressed("dodge") and not _is_dodging:
		_start_dodge()
		get_viewport().set_input_as_handled()


func _start_dodge() -> void:
	_is_dodging = true
	invincible = true
	_dodge_timer = _dodge_duration
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down"),
	)
	if input_dir != Vector2.ZERO:
		_dodge_direction = input_dir.normalized()
	else:
		_dodge_direction = _facing
	_attack_cooldown = _dodge_duration


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


func take_damage(amount: float) -> void:
	if invincible:
		return
	var defense: float = 0.0
	if _has_inventory_evaluator():
		defense = InventoryEvaluator.get_total_stats().get("defense", 0.0)
	var actual_damage := maxf(amount - defense, 0.0)
	current_hp -= actual_damage
	_update_hp_label()
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0.0:
		current_hp = 0.0
		player_died.emit()


func _add_to_group(group_name: String) -> void:
	if not is_in_group(group_name):
		add_to_group(group_name)


func _has_inventory_evaluator() -> bool:
	return Engine.has_singleton("InventoryEvaluator") or is_instance_valid(InventoryEvaluator)
