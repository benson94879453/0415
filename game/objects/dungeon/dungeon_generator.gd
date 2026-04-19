class_name DungeonGenerator
extends RefCounted

## 地牢隨機佈局生成器 (元氣騎士風格)
##
## 規則：
##   1. 先建立「必經路」(spine)：START → MONSTER×N → EXIT 的線性鏈。
##   2. 第 3 個怪物房間有 50% 機率出現在必經路上（避免玩家刻意繞過）。
##   3. 菁英怪物房間一定不在必經路上（作為分支放置）。
##   4. 其餘房間以分支形式接在已有房間旁。
##   5. 所有非怪物房間至少與一個基礎怪物房間相鄰。
##
## 基本參數：
##   - 1 個起始房間
##   - 3 個基礎怪物房間（2~3 個在必經路上，隨機決定）
##   - 1 個出口房間（必經路末端）
##   - 50% 機率出現 1 個菁英怪物房間（分支）
##   - 50% 機率出現 1 個商店房間（分支）

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

	# 決定房間配置
	var monster_count := 3
	var has_elite := randf() < 0.5
	var has_shop := randf() < 0.5
	# 第 3 個怪物房間：50% 必經、50% 分支
	var spine_monsters := monster_count - 1 + (1 if randf() < 0.5 else 0)
	var branch_monsters := monster_count - spine_monsters

	## ── Phase 1: 建立必經路 (spine) ──
	## START → MONSTER × spine_monsters → EXIT
	var start := RoomData.new(Vector2i.ZERO, DungeonRoom.RoomType.START)
	_place_room(start)

	var spine_path: Array[Vector2i] = [Vector2i.ZERO]
	var current_pos := Vector2i.ZERO
	var last_dir: Vector2i = Vector2i.ZERO

	for _i in spine_monsters:
		var next_pos: Variant = _step_to_empty(current_pos, last_dir)
		if next_pos == null:
			push_warning("[DungeonGenerator] 必經路無法延伸")
			break
		last_dir = (next_pos as Vector2i) - current_pos
		current_pos = next_pos as Vector2i
		_place_room(RoomData.new(current_pos, DungeonRoom.RoomType.MONSTER))
		spine_path.append(current_pos)

	# EXIT 在 spine 末端
	var exit_pos: Variant = _step_to_empty(current_pos, last_dir)
	if exit_pos != null:
		current_pos = exit_pos as Vector2i
	else:
		push_warning("[DungeonGenerator] 必經路無法放置出口")
	_place_room(RoomData.new(current_pos, DungeonRoom.RoomType.EXIT))
	spine_path.append(current_pos)

	# 立即連接 spine 鏈，確保必經路暢通
	for i in spine_path.size() - 1:
		_connect_rooms(spine_path[i], spine_path[i + 1])

	## ── Phase 2: 分支房間 ──
	var branch_types: Array[int] = []
	for _i in branch_monsters:
		branch_types.append(DungeonRoom.RoomType.MONSTER)
	if has_elite:
		branch_types.append(DungeonRoom.RoomType.ELITE)
	if has_shop:
		branch_types.append(DungeonRoom.RoomType.SHOP)
	branch_types.shuffle()

	for t in branch_types:
		_place_branch(t)

	## ── Phase 3: 建立連接 ──
	_build_connections()
	_ensure_connectivity()

	return rooms


func _place_room(room: RoomData) -> void:
	rooms.append(room)
	room_map[room.grid_pos] = room


## 從 pos 往隨機空位走一步；avoid_dir 是上一步方向（避免走回頭）
func _step_to_empty(pos: Vector2i, avoid_dir: Vector2i) -> Variant:
	var candidates: Array[Vector2i] = []
	for d in DIRS:
		if d == -avoid_dir and avoid_dir != Vector2i.ZERO:
			continue
		var neighbor: Vector2i = pos + d
		if neighbor not in room_map:
			candidates.append(d)
	if candidates.is_empty():
		# 退而求其次，允許回頭
		for d in DIRS:
			var neighbor: Vector2i = pos + d
			if neighbor not in room_map:
				candidates.append(d)
	if candidates.is_empty():
		return null
	candidates.shuffle()
	return pos + candidates[0]


## 在已有房間旁放置分支房間
func _place_branch(type: int) -> void:
	var parents: Array[RoomData] = []
	for room in rooms:
		# ELITE 只能從怪物房間分支，確保不在必經路上
		if type == DungeonRoom.RoomType.ELITE:
			if room.room_type != DungeonRoom.RoomType.MONSTER:
				continue
		parents.append(room)
	parents.shuffle()

	for parent in parents:
		var pos: Variant = _find_empty_neighbor(parent.grid_pos)
		if pos != null:
			_place_room(RoomData.new(pos as Vector2i, type))
			return
	push_warning("[DungeonGenerator] 無法放置分支房間類型 %d" % type)


## 取得 pos 的一個隨機空鄰位
func _find_empty_neighbor(pos: Vector2i) -> Variant:
	var candidates: Array[Vector2i] = []
	for d in DIRS:
		var neighbor: Vector2i = pos + d
		if neighbor not in room_map:
			candidates.append(neighbor)
	if candidates.is_empty():
		return null
	candidates.shuffle()
	return candidates[0]


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
