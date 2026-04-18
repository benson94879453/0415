extends Node2D

## 家園場景主腳本
## 佈局：左側庭院 ─ 入口 ─ 中央及右側室內房間
## 房間正上方有一扇門，通往正式遊戲關卡。
## 房間左側有入口通往庭院。
## 所有互動皆需按 E ("interact") 觸發。
## 裝飾物與功能解鎖的 API 之後再補。

@onready var door_to_game: Area2D = $Room/DoorToGame
@onready var door_to_courtyard: Area2D = $Room/DoorToCourtyard
@onready var player: CharacterBody2D = $Player

## 裝飾物容器 — 日後動態新增裝飾物用
@onready var decorations: Node2D = $Room/Decorations


func _ready() -> void:
	# 門進入/離開範圍 → 註冊/取消註冊為可互動物件
	_bind_interactable(door_to_game)
	_bind_interactable(door_to_courtyard)

	# 玩家按 E → 統一派發互動
	player.interacted.connect(_on_player_interacted)


## 將一個 Area2D 綁定為可互動物件（進入範圍時註冊，離開時取消）
func _bind_interactable(area: Area2D) -> void:
	area.body_entered.connect(func(body: Node2D) -> void:
		if body == player:
			player.register_interactable(area)
	)
	area.body_exited.connect(func(body: Node2D) -> void:
		if body == player:
			player.unregister_interactable(area)
	)


func _on_player_interacted(target: Area2D) -> void:
	if target == door_to_game:
		_interact_door_to_game()
	elif target == door_to_courtyard:
		_interact_door_to_courtyard()


func _interact_door_to_game() -> void:
	print("[Homestead] 按下 E → 進入地牢")
	SceneTransition.change_scene("res://game/objects/dungeon/dungeon.tscn")


func _interact_door_to_courtyard() -> void:
	print("[Homestead] 按下 E → 進入庭院區域")
