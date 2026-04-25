class_name DungeonGenerator
extends RefCounted

## 按需地牢生成器
##
## 狀態化 API：初始化時只建立 START 房間，
## 隨玩家向北推進時逐一建立新房間。

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1),  # UP
	Vector2i(0, 1),   # DOWN
	Vector2i(-1, 0),  # LEFT
	Vector2i(1, 0),   # RIGHT
]

## Dir enum 對應 (與 DungeonRoom.Dir 一致)
const DIR_UP    := 0
const DIR_DOWN  := 1
const DIR_LEFT  := 2
const DIR_RIGHT := 3

## Vector2i offset → Dir
const OFFSET_TO_DIR: Dictionary = {
	Vector2i(0, -1): DIR_UP,
	Vector2i(0, 1):  DIR_DOWN,
	Vector2i(-1, 0): DIR_LEFT,
	Vector2i(1, 0):  DIR_RIGHT,
}

## Dir → 反方向
const OPPOSITE_DIR: Dictionary = {
	DIR_UP: DIR_DOWN,
	DIR_DOWN: DIR_UP,
	DIR_LEFT: DIR_RIGHT,
	DIR_RIGHT: DIR_LEFT,
}

## 非 START 房間上限；達到後下一次自動成為 EXIT
const ROOM_CAP: int = 4


class RoomData:
	var grid_pos: Vector2i
	var room_type: DungeonRoom.RoomType
	var connections: Array[int] = []  # DungeonRoom.Dir values

	func _init(p_pos: Vector2i, p_type: DungeonRoom.RoomType) -> void:
		grid_pos = p_pos
		room_type = p_type


## 生成狀態
var rooms: Array[RoomData] = []
var room_map: Dictionary = {}  # Vector2i → RoomData
var rooms_built: int = 0  # 非 START 房間計數


## 初始化一次 run：清空狀態，建立 START 房間於 (0,0)
func init_run() -> RoomData:
	rooms.clear()
	room_map.clear()
	rooms_built = 0
	var start := RoomData.new(Vector2i.ZERO, DungeonRoom.RoomType.START)
	_place_room(start)
	print("[DungeonGenerator] init_run: START room placed at (0,0)")
	return start


## 計算 from_pos 正北方的格子座標
func get_next_north_pos(from_pos: Vector2i) -> Vector2i:
	return from_pos + Vector2i(0, -1)


## 是否已達上限，下次應自動設為 EXIT
func should_auto_exit() -> bool:
	return rooms_built >= ROOM_CAP


## 在 from_pos 正北方建立新房間。
## 若目標位置已佔用則回傳 null 並印出警告。
## 若 should_auto_exit() 為 true，無論傳入的 room_type 為何都自動改為 EXIT。
func create_north_room(from_pos: Vector2i, room_type: DungeonRoom.RoomType) -> RoomData:
	var target_pos := get_next_north_pos(from_pos)

	if target_pos in room_map:
		push_warning("[DungeonGenerator] create_north_room: position %s already occupied, rejected" % target_pos)
		return null

	# 自動 EXIT
	if should_auto_exit():
		print("[DungeonGenerator] create_north_room: rooms_built(%d) >= ROOM_CAP(%d), auto-typing as EXIT" % [rooms_built, ROOM_CAP])
		room_type = DungeonRoom.RoomType.EXIT

	var room := RoomData.new(target_pos, room_type)
	_place_room(room)
	_connect_rooms(from_pos, target_pos)
	rooms_built += 1

	print("[DungeonGenerator] create_north_room: %s room placed at %s (rooms_built=%d)" % [
		DungeonRoom.RoomType.keys()[room_type],
		target_pos,
		rooms_built,
	])
	return room


func _place_room(room: RoomData) -> void:
	rooms.append(room)
	room_map[room.grid_pos] = room


func _connect_rooms(pos_a: Vector2i, pos_b: Vector2i) -> void:
	var offset: Vector2i = pos_b - pos_a
	var dir_a: int = OFFSET_TO_DIR[offset] as int
	var dir_b: int = OPPOSITE_DIR[dir_a] as int
	var room_a: RoomData = room_map[pos_a]
	var room_b: RoomData = room_map[pos_b]
	if dir_a not in room_a.connections:
		room_a.connections.append(dir_a)
	if dir_b not in room_b.connections:
		room_b.connections.append(dir_b)
