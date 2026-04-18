extends Control

@onready var input: StartScreenInput = %Input
@onready var start_button: Button = %StartButton
@onready var settings_button: TextureButton = %SettingsButton
@onready var settings_panel: PanelContainer = %SettingsPanel

@onready var master_volume: VolumeSlider = %MasterVolume
@onready var sfx_volume: VolumeSlider = %SFXVolume
@onready var music_volume: VolumeSlider = %MusicVolume


func _ready() -> void:
	start_button.pressed.connect(input.action_start)
	settings_button.pressed.connect(input.action_settings)

	input.start_pressed.connect(_on_start)
	input.settings_toggled.connect(_on_settings_toggled)

	settings_panel.visible = false

	_init_volume_sliders()


func _init_volume_sliders() -> void:
	var sliders: Array[VolumeSlider] = [master_volume, sfx_volume, music_volume]
	for s in sliders:
		s.set_volume_linear(AudioSettings.get_volume(s.bus_name))
		s.volume_changed.connect(_on_volume_changed)


func _on_volume_changed(bus_name: String, value: float) -> void:
	AudioSettings.set_volume(bus_name, value)
	AudioSettings.save_settings()


func _on_start() -> void:
	print("[StartScreen] 開始遊戲 → 家園場景")
	SceneTransition.change_scene("res://game/objects/homestead/homestead.tscn")


func _on_settings_toggled(is_open: bool) -> void:
	settings_panel.visible = is_open
	print("[StartScreen] 設定面板: ", "開啟" if is_open else "關閉")
