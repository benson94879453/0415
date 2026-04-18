extends Node

## 全域音訊設定管理（Autoload）
## 負責初始化音效匯流排佈局，以及持久化音量設定。

const SAVE_PATH: String = "user://audio_settings.cfg"

var _config: ConfigFile = ConfigFile.new()

# 預設音量值（0~100 線性）
var _defaults: Dictionary = {
	"Master": 80.0,
	"SFX": 80.0,
	"Music": 80.0,
}


func _ready() -> void:
	# 載入音效匯流排佈局
	var bus_layout := load("res://game/assets/audio/default_bus_layout.tres") as AudioBusLayout
	if bus_layout:
		AudioServer.set_bus_layout(bus_layout)

	load_settings()


func get_volume(bus_name: String) -> float:
	return _config.get_value("audio", bus_name, _defaults.get(bus_name, 80.0))


func set_volume(bus_name: String, value: float) -> void:
	_config.set_value("audio", bus_name, value)


func save_settings() -> void:
	_config.save(SAVE_PATH)


func load_settings() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_config.load(SAVE_PATH)
