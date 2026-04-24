extends CharacterBody2D
class_name EnemyBase

## 基礎敵人：追蹤玩家、接觸造成傷害、可被擊殺
## 加入 "enemies" 群組供 CombatPlayer / Projectile 搜尋目標。

@export var max_hp: float = 30.0
@export var move_speed: float = 80.0
@export var contact_damage: float = 5.0

var current_hp: float = 30.0
var _target: Node2D = null
var _is_dead: bool = false
var _contact_damage_cooldown: float = 0.0

var _body_rect: ColorRect
var _contact_area: Area2D
var _wander_direction: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _hurt_timer: float = 0.0


func _ready() -> void:
	current_hp = max_hp
	add_to_group("enemies")
	_create_visual()
	_create_contact_area()


func _create_visual() -> void:
	_body_rect = ColorRect.new()
	_body_rect.name = "EnemyBody"
	_body_rect.size = Vector2(24, 24)
	_body_rect.position = Vector2(-12, -12)
	_body_rect.color = Color.RED
	add_child(_body_rect)


func _create_contact_area() -> void:
	_contact_area = Area2D.new()
	_contact_area.name = "ContactArea"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	_contact_area.add_child(shape)
	add_child(_contact_area)


func setup(player: Node2D) -> void:
	_target = player


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_update_hurt_flash(delta)
	_contact_damage_cooldown = maxf(_contact_damage_cooldown - delta, 0.0)

	if _target == null or not is_instance_valid(_target):
		_target = _find_player()

	if _target:
		_chase_target()
	else:
		_wander(delta)

	move_and_slide()
	_check_contact_damage()


func _find_player() -> Node2D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and p is Node2D:
			return p
	return null


func _chase_target() -> void:
	var direction: Vector2 = (_target.global_position - global_position).normalized()
	velocity = direction * move_speed


func _wander(delta: float) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
		_wander_timer = randf_range(1.0, 3.0)
	velocity = _wander_direction * move_speed * 0.3


func _check_contact_damage() -> void:
	if _contact_damage_cooldown > 0.0:
		return
	if _contact_area == null:
		return
	var bodies: Array[Node2D] = _contact_area.get_overlapping_bodies()
	for body in bodies:
		if body == self:
			continue
		if body.has_method("take_damage") and body.has_signal("player_died"):
			if not body.invincible:
				body.take_damage(contact_damage)
				_contact_damage_cooldown = 0.5
				return


func take_damage(amount: float) -> void:
	if _is_dead:
		return
	current_hp -= amount
	_start_hurt_flash()
	if current_hp <= 0.0:
		current_hp = 0.0
		die()


func _start_hurt_flash() -> void:
	_hurt_timer = 0.1
	if _body_rect:
		_body_rect.color = Color.WHITE


func _update_hurt_flash(delta: float) -> void:
	if _hurt_timer > 0.0:
		_hurt_timer -= delta
		if _hurt_timer <= 0.0 and _body_rect:
			_body_rect.color = Color.RED


func die() -> void:
	_is_dead = true
	remove_from_group("enemies")
	_play_death_effect()


func _play_death_effect() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_body_rect, "color", Color(Color.RED, 0.0), 0.3)
	tween.tween_callback(queue_free)
