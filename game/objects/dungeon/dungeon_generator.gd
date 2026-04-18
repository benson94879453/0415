class_name DungeonGenerator
extends RefCounted

## 地牢隨機佈局生成器 (元氣騎士風格)
##
## 規則：
##   1. 從起始房間出發，在網格上向四鄰擴展放置房間。
##   2. 相鄰房間不一定有通道，但每個房間至少與一個房間相通。
##   3. 不存在無法到達的房間（從起點可達所有房間）。
##   4. 所有非怪物房間（起點、菁英、商店、出口）必須與至少一個基礎怪物房間相鄰。
##
## 基本參數：
##   - 1 個起始房間
##   - 3 個基礎怪物房間
##   - 1 個出口房間（通往下一層）
##   - 50% 機率出現 1 個菁英怪物房間
##   - 50% 機率出現 1 個商店房間

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


class RoomData:
	var grid_pos: Vector2i
	var room_type: DungeonRoom.RoomType
	var connections: Array[int] = []  # DungeonRoom.Dir values

	func _init(p_pos: Vector2i, p_type: DungeonRoom.RoomType) -> void:
		grid_pos = p_pos
		room_type = p_type


## 生成結果
var rooms: Array[RoomData] = []
var room_map: Dictionary = {}  # Vector2i → RoomData


func generate() -> Array[RoomData]:
	rooms.clear()
	room_map.clear()

	# 決定本次有哪些房間要放
	var types_to_place: Array[int] = []
	# 3 個基礎怪物房間
	for i in 3:
		types_to_place.append(DungeonRoom.RoomType.MONSTER)
	# 50% 菁英
	if randf() < 0.5:
		types_to_place.append(DungeonRoom.RoomType.ELITE)
	# 50% 商店
	if randf() < 0.5:
		types_to_place.append(DungeonRoom.RoomType.SHOP)
	# 1 個出口 (放在最後，確保離起點較遠)
	types_to_place.append(DungeonRoom.RoomType.EXIT)

	# 1) 放置起始房間
	var start := RoomData.new(Vector2i.ZERO, DungeonRoom.RoomType.START)
	_place_room(start)

	# 2) 先放所有怪物房間 (因為其他房間需要與怪物房相鄰)
	var monster_types: Array[int] = []
	var special_types: Array[int] = []
	for t in types_to_place:
		if t == DungeonRoom.RoomType.MONSTER:
			monster_types.append(t)
		else:
			special_types.append(t)

	# 放怪物房間：從已放置的房間中挑選空鄰位
	for t in monster_types:
w		var pos: Variant = _find_adjacent_empty_pos()
		if pos == null:
			push_warning("[DungeonGenerator] 無法放置怪物房間")
			continue
		var room := RoomData.new(pos as Vector2i, t)
		_place_room(room)

	# 3) 放特殊房間 — 必須與至少一個怪物房間相鄰
	for t in special_types:
		var pos: Variant = _find_pos_adjacent_to_monster()
		if pos == null:
			# 退而求其次：任意空鄰位
			pos = _find_adjacent_empty_pos()
		if pos == null:
			push_warning("[DungeonGenerator] 無法放置房間類型 %d" % t)
			continue
		var room := RoomData.new(pos as Vector2i, t)
		_place_room(room)

	# 4) 建立連接 (門)
	_build_connections()

	# 5) 驗證連通性，若不連通則補連接
	_ensure_connectivity()

	return rooms


func _place_room(room: RoomData) -> void:
	rooms.append(room)
	room_map[room.grid_pos] = room


## 在所有已放置房間的空鄰位中隨機選一個
func _find_adjacent_empty_pos() -> Variant:
	var candidates: Array[Vector2i] = []
	for room in rooms:
		for d in DIRS:
			var neighbor_pos: Vector2i = room.grid_pos + d
			if neighbor_pos not in room_map:
				candidates.append(neighbor_pos)
	if candidates.is_empty():
		return null
	candidates.shuffle()
	return candidates[0]


## 找一個空位，且該空位至少與一個怪物房間相鄰
func _find_pos_adjacent_to_monster() -> Variant:
	var candidates: Array[Vector2i] = []
	for room in rooms:
		for d in DIRS:
			var neighbor_pos: Vector2i = room.grid_pos + d
			if neighbor_pos in room_map:
				continue
			# 檢查此空位的所有鄰居中是否有怪物房
			if _has_monster_neighbor(neighbor_pos):
				candidates.append(neighbor_pos)
	if candidates.is_empty():
		return null
	candidates.shuffle()
	return candidates[0]


func _has_monster_neighbor(pos: Vector2i) -> bool:
	for d in DIRS:
		var np: Vector2i = pos + d
		if np in room_map:
			var r: RoomData = room_map[np]
			if r.room_type == DungeonRoom.RoomType.MONSTER:
				return true
	return false


## 為每對相鄰的房間建立連接 (門)
## 確保：所有非怪物房間至少有一條連接通向怪物房間
func _build_connections() -> void:
	# 先為每對相鄰房間建立候選邊
	var edges: Array[Array] = []
	var visited_pairs: Dictionary = {}
	for room in rooms:
		for d in DIRS:
			var np: Vector2i = room.grid_pos + d
			if np in room_map:
				var pair_key: String = _pair_key(room.grid_pos, np)
				if pair_key not in visited_pairs:
					visited_pairs[pair_key] = true
					edges.append([room.grid_pos, np])

	# 必要連接：確保每個非怪物房間至少連到一個怪物房間
	var required_edges: Dictionary = {}  # pair_key → true
	for room in rooms:
		if room.room_type == DungeonRoom.RoomType.MONSTER:
			continue
		# 找到相鄰的怪物房間並建立必要連接
		var found: bool = false
		for d in DIRS:
			var np: Vector2i = room.grid_pos + d
			if np in room_map:
				var neighbor: RoomData = room_map[np]
				if neighbor.room_type == DungeonRoom.RoomType.MONSTER:
					required_edges[_pair_key(room.grid_pos, np)] = true
					found = true
					break
		if not found:
			# 沒有怪物鄰居，至少連接到任意鄰居
			for d in DIRS:
				var np: Vector2i = room.grid_pos + d
				if np in room_map:
					required_edges[_pair_key(room.grid_pos, np)] = true
					break

	# 用 Kruskal-like 方式確保連通性
	# 先加入所有必要邊，再隨機加入剩餘邊直到連通
	var uf := _UnionFind.new(rooms)

	# 加入必要邊
	for edge in edges:
		var pk: String = _pair_key(edge[0], edge[1])
		if pk in required_edges:
			_connect_rooms(edge[0], edge[1])
			uf.union(edge[0], edge[1])

	# 隨機排序剩餘邊
	edges.shuffle()
	for edge in edges:
		var pk: String = _pair_key(edge[0], edge[1])
		if pk in required_edges:
			continue
		# 如果兩個房間尚未連通，則連接
		if uf.find(edge[0]) != uf.find(edge[1]):
			_connect_rooms(edge[0], edge[1])
			uf.union(edge[0], edge[1])


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


func _ensure_connectivity() -> void:
	if rooms.is_empty():
		return
	# BFS 從起點驗證
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [rooms[0].grid_pos]
	visited[rooms[0].grid_pos] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var room: RoomData = room_map[current]
		for dir in room.connections:
			var offset: Vector2i = DIRS[dir]
			var np: Vector2i = current + offset
			if np in room_map and np not in visited:
				visited[np] = true
				queue.append(np)
	# 如果有未訪問的房間，強制連接
	for room in rooms:
		if room.grid_pos not in visited:
			# 找到一個已訪問的鄰居並連接
			for d in DIRS:
				var np: Vector2i = room.grid_pos + d
				if np in visited:
					_connect_rooms(room.grid_pos, np)
					visited[room.grid_pos] = true
					break


func _pair_key(a: Vector2i, b: Vector2i) -> String:
	if a < b:
		return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d-%d,%d" % [b.x, b.y, a.x, a.y]


## 簡易 Union-Find
class _UnionFind:
	var parent: Dictionary = {}  # Vector2i → Vector2i

	func _init(room_list: Array[RoomData]) -> void:
		for r in room_list:
			parent[r.grid_pos] = r.grid_pos

	func find(pos: Vector2i) -> Vector2i:
		if parent[pos] != pos:
			parent[pos] = find(parent[pos] as Vector2i)
		return parent[pos] as Vector2i

	func union(a: Vector2i, b: Vector2i) -> void:
		var ra: Vector2i = find(a)
		var rb: Vector2i = find(b)
		if ra != rb:
			parent[ra] = rb
