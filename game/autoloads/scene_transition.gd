extends CanvasLayer

## 全域場景轉場管理（Autoload）
## 提供 fade out → 切換場景 → fade in 的可複用轉場效果。
##
## 用法：
##   SceneTransition.change_scene("res://game/objects/dungeon/dungeon.tscn")
##   SceneTransition.change_scene("res://...", 0.5)  # 自訂淡入淡出時長

signal transition_started
signal scene_changed
signal transition_finished

@onready var color_rect: ColorRect = $ColorRect
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var _next_scene_path: String = ""
var _is_transitioning: bool = false

const DEFAULT_DURATION: float = 0.4


func _ready() -> void:
	layer = 100
	_setup_color_rect()
	_setup_animations(DEFAULT_DURATION)
	color_rect.visible = false


func change_scene(scene_path: String, duration: float = DEFAULT_DURATION) -> void:
	if _is_transitioning:
		push_warning("[SceneTransition] 轉場進行中，忽略重複呼叫")
		return
	_is_transitioning = true
	_next_scene_path = scene_path

	if not is_equal_approx(duration, DEFAULT_DURATION):
		_setup_animations(duration)

	transition_started.emit()
	color_rect.visible = true
	anim_player.play("fade_out")
	await anim_player.animation_finished

	get_tree().change_scene_to_file(_next_scene_path)
	scene_changed.emit()

	# 等一幀讓新場景初始化
	await get_tree().process_frame

	anim_player.play("fade_in")
	await anim_player.animation_finished

	color_rect.visible = false
	_is_transitioning = false
	transition_finished.emit()


## 僅做 fade out → 執行回呼 → fade in，不切換場景。
## 用於同一場景內的房間轉場等。
func fade_only(callback: Callable, duration: float = DEFAULT_DURATION) -> void:
	if _is_transitioning:
		push_warning("[SceneTransition] 轉場進行中，忽略重複呼叫")
		return
	_is_transitioning = true

	if not is_equal_approx(duration, DEFAULT_DURATION):
		_setup_animations(duration)

	transition_started.emit()
	color_rect.visible = true
	anim_player.play("fade_out")
	await anim_player.animation_finished

	# 在全黑時執行回呼（移動玩家、切換房間等）
	callback.call()
	scene_changed.emit()

	await get_tree().process_frame

	anim_player.play("fade_in")
	await anim_player.animation_finished

	color_rect.visible = false
	_is_transitioning = false
	transition_finished.emit()


func is_transitioning() -> bool:
	return _is_transitioning


func _setup_color_rect() -> void:
	if not color_rect:
		color_rect = ColorRect.new()
		color_rect.name = "ColorRect"
		add_child(color_rect)
	color_rect.color = Color(0, 0, 0, 0)
	color_rect.anchors_preset = Control.PRESET_FULL_RECT
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _setup_animations(duration: float) -> void:
	if not anim_player:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		add_child(anim_player)

	var lib: AnimationLibrary
	if anim_player.has_animation_library(""):
		lib = anim_player.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library("", lib)

	# fade_out: alpha 0 → 1 (畫面變黑)
	var fade_out := Animation.new()
	fade_out.length = duration
	var track_out := fade_out.add_track(Animation.TYPE_VALUE)
	fade_out.track_set_path(track_out, "ColorRect:color")
	fade_out.track_insert_key(track_out, 0.0, Color(0, 0, 0, 0))
	fade_out.track_insert_key(track_out, duration, Color(0, 0, 0, 1))
	fade_out.track_set_interpolation_type(track_out, Animation.INTERPOLATION_CUBIC)

	# fade_in: alpha 1 → 0 (畫面亮起)
	var fade_in := Animation.new()
	fade_in.length = duration
	var track_in := fade_in.add_track(Animation.TYPE_VALUE)
	fade_in.track_set_path(track_in, "ColorRect:color")
	fade_in.track_insert_key(track_in, 0.0, Color(0, 0, 0, 1))
	fade_in.track_insert_key(track_in, duration, Color(0, 0, 0, 0))
	fade_in.track_set_interpolation_type(track_in, Animation.INTERPOLATION_CUBIC)

	if lib.has_animation("fade_out"):
		lib.remove_animation("fade_out")
	if lib.has_animation("fade_in"):
		lib.remove_animation("fade_in")
	lib.add_animation("fade_out", fade_out)
	lib.add_animation("fade_in", fade_in)
