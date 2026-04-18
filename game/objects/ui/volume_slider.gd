class_name VolumeSlider
extends HBoxContainer

## 可複用的音量滑動條模板元件。
## 將 0~100 的線性值轉換為類似分貝的對數倍率套用到 AudioServer。
##
## 使用方式：將此場景實例化後，透過 setup() 設定對應的音效匯流排。

signal volume_changed(bus_name: String, linear_value: float)

@export var bus_name: String = "Master"
@export var label_text: String = "音量"
@export var default_value: float = 80.0

@onready var label: Label = $Label
@onready var slider: HSlider = $HSlider
@onready var value_label: Label = $ValueLabel

## 最小分貝值（靜音門檻）
const MIN_DB: float = -60.0


func _ready() -> void:
	label.text = label_text
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = default_value
	_update_value_label(default_value)
	_apply_volume(default_value)
	slider.value_changed.connect(_on_slider_value_changed)


func setup(p_bus_name: String, p_label: String, p_default: float = 80.0) -> void:
	bus_name = p_bus_name
	label_text = p_label
	default_value = p_default
	if is_node_ready():
		label.text = label_text
		slider.value = default_value
		_apply_volume(default_value)


func _on_slider_value_changed(value: float) -> void:
	_update_value_label(value)
	_apply_volume(value)
	volume_changed.emit(bus_name, value)


func _update_value_label(value: float) -> void:
	value_label.text = str(int(value))


func _apply_volume(value: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		push_warning("VolumeSlider: 找不到音效匯流排 '%s'" % bus_name)
		return

	if value <= 0.0:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		# 線性 0~100 → 對數分貝曲線
		# 公式: dB = MIN_DB + (MIN_DB 的絕對值) * (value/100)^2  的反向
		# 更直覺: 使用 linear_to_db 但先做平方曲線讓低音量區域更細緻
		var normalized: float = value / 100.0
		var curved: float = normalized * normalized  # 平方曲線，模擬分貝感知
		var db: float = linear_to_db(curved)
		AudioServer.set_bus_volume_db(bus_idx, db)


func get_volume_linear() -> float:
	return slider.value


func set_volume_linear(value: float) -> void:
	slider.value = clampf(value, 0.0, 100.0)
