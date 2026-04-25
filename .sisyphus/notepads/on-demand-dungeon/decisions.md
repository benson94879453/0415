# Decisions

## [2026-04-25] Pre-Plan Decisions
- Clear detection: poll "enemies" group count within room bounds → 0 = cleared
- Player type: switch dungeon.tscn to combat_player.gd (not homestead/player.gd)
- Blueprint reward: fixed 1 random from allowed pool (no rarity/weighting)
- TREASURE excluded from reward pool (no enum support in RoomType)
- North-only advancement with south backtracking allowed
- 3 fixed north slots: center=door, left/right=blank walls
- START room immediately cleared on first visit
- Run cap: EXIT auto-placed after 4 player-authored rooms
- Keyboard fallback: Tab cycles slots, E applies first compatible blueprint
- No new input actions added to project.godot
