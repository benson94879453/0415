class_name StartScreenInput
extends Node

## 管理開始畫面的輸入動作：
##   - "start"    : 開始遊戲
##   - "settings" : 開關設定面板

signal start_pressed
signal settings_toggled(is_open: bool)

var _settings_open: bool = false





func action_start() -> void:
	start_pressed.emit()


func action_settings() -> void:
	_settings_open = not _settings_open
	settings_toggled.emit(_settings_open)


func is_settings_open() -> bool:
	return _settings_open
