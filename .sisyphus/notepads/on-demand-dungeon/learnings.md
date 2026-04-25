# Learnings

## [2026-04-25] Initial Codebase Analysis
- DungeonGenerator uses spine+branch random layout with Union-Find connectivity
- DungeonRoom dynamically creates walls (StaticBody2D) and doors (Area2D) based on connections
- door_areas: Dictionary = {} maps Dir enum to Area2D
- InventoryUI has full drag/drop with rotation, preview, and item_dropped_from_inventory signal
- CombatPlayer has interacted signal, register_interactable/unregister_interactable, HP system, auto-attack
- dungeon.tscn currently uses homestead/player.gd (no combat) - must swap to combat_player.gd
- EnemyBase adds to "enemies" group on _ready, removes on die()
- Blueprint items exist in items.json: bp_monster_room, bp_elite_room, bp_shop_room, bp_treasure_room
- DungeonRoom.RoomType enum: START, MONSTER, ELITE, SHOP, EXIT (no TREASURE)
- Input actions: interact=E, inventory=T, dropitem=Q, dodge=Space, map=M
- Room spacing: grid_to_world uses (ROOM_WIDTH+800, ROOM_HEIGHT+800) per grid unit
