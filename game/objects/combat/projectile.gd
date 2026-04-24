extends Area2D
class_name Projectile

## 遠程武器發射的投射物
## 使用 Area2D + CollisionShape2D 偵測碰撞，以直線飛行並在命中敵人後消失。

var direction: Vector2 = Vector2.RIGHT
var speed: float = 300.0
var damage: float = 5.0

var _lifetime: float = 3.0
var _collision_shape: CollisionShape2D


func _ready() -> void:
	_create_visual()
	_create_collision()
	body_entered.connect(_on_body_entered)


func _create_visual() -> void:
	var body := ColorRect.new()
	body.name = "ProjectileBody"
	body.size = Vector2(8, 8)
	body.position = Vector2(-4, -4)
	body.color = Color.YELLOW
	add_child(body)


func _create_collision() -> void:
	_collision_shape = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 6.0
	_collision_shape.shape = shape
	add_child(_collision_shape)


func _process(delta: float) -> void:
	position += direction * speed * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
