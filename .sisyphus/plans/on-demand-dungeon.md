# On-Demand Dungeon Core Loop

## TL;DR
> **Summary**: Replace the current pre-generated dungeon layout with a north-forward, room-at-a-time flow that reveals 3 north-wall slots after a room is cleared, then lets blueprints override an existing door or create a new door from a blank wall. Preserve the current grid/room/interaction architecture wherever possible.
> **Deliverables**:
> - On-demand dungeon generation replacing full-map upfront generation
> - Dedicated `Door` and `WallSlot` nodes/scenes integrated into `DungeonRoom`
> - Blueprint drag/drop targeting from inventory onto door slots
> - Keyboard fallback for slot selection and blueprint application
> - Manual QA flow for start room, clear room, override, create, backtrack, and exit cap
> **Effort**: Medium
> **Parallel**: YES - 2 waves
> **Critical Path**: 1 → 2 → 3/4 → 5 → 6 → 7 → 8

## Context
### Original Request
- 實作單向推進與門路系統的核心體驗。
- 重構 `dungeon_generator.gd` 為單房按需生成。
- 建立 `Door` 與 `WallSlot` 節點。
- 當物品類型為 `blueprint` 且與門位重疊時，執行房間替換；拖到空白牆壁則炸牆建門。

### Interview Summary
- 本輪只做核心體驗，不納入 Mutation、Pitfall、Bag Mimic、Blood Altar、存檔、平衡、美術 polish。
- 互動輸入以滑鼠拖放為主，需有鍵盤備援。
- 不建立測試框架；驗證採 agent 可重現的手動 QA 場景。

### Metis Review (gaps addressed)
- 目前 repo 沒有明確房間清理完成機制；本計畫預設以「目前房間內 `enemies` 群組數量歸零」視為 cleared。
- `dungeon.tscn` 目前掛的是 `homestead/player.gd`，但地牢已依賴 `CombatPlayer` 型 API；本計畫明確改用 `combat_player.gd`，不做戰鬥重構。
- blueprint 已存在於 `game/data/items.json`，但 reward loop 未存在；本計畫限定為簡易固定掉落，不做稀有度/平衡設計。
- `bp_treasure_room` 已存在，但 `DungeonRoom.RoomType` 沒有 `TREASURE`；本計畫明確排除 treasure blueprint 進入 reward pool，避免 runtime mismatch。
- 線性模式下仍允許南向回頭；北牆 slots 僅在首次 clear 後顯示，不會重複發獎或重置。

## Work Objectives
### Core Objective
把目前 `DungeonGenerator.generate()` 的「一次產整張圖」改成「只維護已建立房間與北向候選 slot」，讓玩家在每次清房後透過 Door/WallSlot + blueprint 選擇下一個房間，形成可回頭但只能向北擴展的新地牢流程。

### Deliverables
- `dungeon_generator.gd` 支援 run-state 與按需建立單一房間資料，而不是一次回傳完整 rooms 陣列。
- `Dungeon` 支援動態建立/覆寫下一房、回頭、run cap 與 EXIT auto-placement。
- `DungeonRoom` 支援 room clear、north-slot reveal、slot state 維護。
- 新增 `Door` / `WallSlot` 節點或場景，供互動與視覺分離。
- `InventoryUI` 與地牢互動層整合 blueprint 拖曳偵測與鍵盤備援。

### Definition of Done (verifiable conditions with commands)
- `godot4 --path . --scene res://game/objects/dungeon/dungeon.tscn` 可啟動且無 parse error。
- 進入起始房後，不需戰鬥即可看到 3 個北牆 slot。
- 清空怪物房後，北牆 slot 顯示，並新增 1 張非 treasure blueprint 到背包。
- 將 blueprint 拖到既有 door 可覆寫目標房型；拖到 blank wall 可建立新 door/房間。
- 玩家可從北方新房走回南方舊房；舊房不重置、不重複發 slot/獎勵。
- 放到第 4 個玩家選擇房後，下一個自動為 EXIT；進入 EXIT 後觸發 run 完成流程。

### Must Have
- 保留現有 `DungeonRoom.grid_to_world()`、`connections`、`door_areas` 的資料模式。
- Door / WallSlot 都必須是 `Area2D` 互動節點，與現有互動註冊模式一致。
- 只在北牆顯示 3 個 slot：中央預設為既有 door，左右為 blank wall。
- START 房首次進入即視為 cleared。
- reward pool 僅允許 `bp_monster_room`、`bp_elite_room`、`bp_shop_room`。

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- 不新增 mutation / pitfall / mimic / altar / biome / boss 系統。
- 不重做整套戰鬥；僅做讓目前地牢流程可抵達 cleared 狀態所需的最小整合。
- 不建立完整 loot table、rarity、經濟平衡。
- 不新增新 input action 到 `project.godot`；鍵盤備援直接使用 `KEY_TAB` + 已存在的 `interact`。
- 不把 blueprint 拖出背包後仍沿用 ground-drop 行為；blueprint 在 dungeon 內必須先走 slot-targeting 分支。

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: none + manual agent-executed QA (repo 無正式測試框架)
- QA policy: Every task includes deterministic verification scenarios and evidence capture
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: foundation/runtime refactor (`dungeon_generator.gd`, `dungeon.gd`, `dungeon_room.gd`, `dungeon.tscn`)

Wave 2: interaction layer (`Door`, `WallSlot`, blueprint drag/drop targeting, keyboard fallback, reward loop, EXIT cap)

### Dependency Matrix (full, all tasks)
- 1 blocks 2, 3, 5, 6, 7, 8
- 2 blocks 3, 6, 7, 8
- 3 blocks 5, 6, 7, 8
- 4 blocks 5, 6, 7
- 5 blocks 6, 7, 8
- 6 blocks 7, 8
- 7 blocks 8

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 → 4 tasks → `deep`, `unspecified-high`, `quick`
- Wave 2 → 4 tasks → `visual-engineering`, `deep`, `unspecified-high`, `quick`
- Final Verification → 4 tasks → `oracle`, `unspecified-high`, `deep`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Refactor generator into run-state driven on-demand model

  **What to do**: Replace `DungeonGenerator.generate()` full-layout behavior with a stateful API that can initialize a run, register created rooms in `rooms` / `room_map`, reserve the fixed north-slot layout, and create one room at a time on demand. Keep `DIRS`, dir constants, `RoomData`, and connection bookkeeping, but remove spine/branch/Union-Find logic from the runtime path. Add explicit helper methods for: initializing START room, creating the default north room, creating a room from blueprint override, creating a room from blank wall slot, auto-placing EXIT after the configured room cap, and preventing duplicate room creation at occupied positions.
  **Must NOT do**: Do not keep the old random full-map generation as the active dungeon path. Do not introduce diagonal positions, variable slot counts, or a generic graph system.

  **Recommended Agent Profile**:
  - Category: `deep` - Reason: central runtime architecture change with downstream blockers.
  - Skills: `[]` - No special skill needed.
  - Omitted: `['/playwright']` - No browser/UI automation required.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: 2,3,5,6,7,8 | Blocked By: none

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `game/objects/dungeon/dungeon_generator.gd:20-47` - existing direction constants and offset mappings must remain source-of-truth.
  - Pattern: `game/objects/dungeon/dungeon_generator.gd:50-62` - retain `RoomData`, `rooms`, and `room_map` as the canonical dungeon data containers.
  - Anti-pattern to replace: `game/objects/dungeon/dungeon_generator.gd:65-126` - current `generate()` eagerly creates spine + branches.
  - Pattern: `game/objects/dungeon/dungeon_generator.gd:248-257` - reuse `_connect_rooms()` for directional connection bookkeeping.
  - Constraint source: `game/objects/dungeon/dungeon_room.gd:16-24` - room directions and dimensions already defined here.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `dungeon_generator.gd` exposes a startup path that creates only START room data at initialization.
  - [ ] Creating a room for an already-occupied grid position is rejected deterministically.
  - [ ] After four player-authored northward expansions, the next generated room type is `EXIT` automatically.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Generator initializes single-room run
    Tool: Bash
    Steps: Launch `godot4 --path . --scene res://game/objects/dungeon/dungeon.tscn`; inspect logs from startup instrumentation for generated room count.
    Expected: Startup creates only `(0,0)` START room before any slot interaction.
    Evidence: .sisyphus/evidence/task-1-generator-init.txt

  Scenario: Duplicate room creation is blocked
    Tool: Bash
    Steps: Trigger the same slot creation path twice in a debug run or via temporary deterministic harness; inspect logs.
    Expected: Second creation is refused with a clear log and no duplicate node in `_room_nodes`.
    Evidence: .sisyphus/evidence/task-1-generator-duplicate.txt
  ```

  **Commit**: YES | Message: `refactor(dungeon): convert generator to on-demand flow` | Files: `game/objects/dungeon/dungeon_generator.gd`

- [x] 2. Convert dungeon runtime to dynamic room creation and combat-capable player

  **What to do**: Update `dungeon.tscn` to use `res://game/objects/combat/combat_player.gd` for the dungeon Player node. Refactor `dungeon.gd` so `_generate_dungeon()` becomes an initialization path that creates only START, wires inventory/UI, and stores generator/runtime state for later room creation. Add runtime methods to spawn a `DungeonRoom` node from `RoomData`, bind its door/slot interactables, move into dynamically created rooms, support southward backtracking, and run the EXIT completion flow. Remove hardcoded `_spawn_test_enemies()` from startup path and replace it with room-type-based spawning hooks that can be called when a MONSTER/ELITE room is first materialized.
  **Must NOT do**: Do not leave `homestead/player.gd` active in dungeon. Do not instantiate the whole run at `_ready()`. Do not delete previous rooms when moving forward.

  **Recommended Agent Profile**:
  - Category: `deep` - Reason: integrates generator, player, transition, and lifecycle rules.
  - Skills: `[]` - No special skill needed.
  - Omitted: `['/frontend-ui-ux']` - Not a layout/design task.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: 3,6,7,8 | Blocked By: 1

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `game/objects/dungeon/dungeon.gd:30-46` - current room instantiation loop to replace with single-room/dynamic creation.
  - Pattern: `game/objects/dungeon/dungeon.gd:47-64` - inventory/map setup should remain intact.
  - Anti-pattern to remove: `game/objects/dungeon/dungeon.gd:65-75` - current startup test items/enemy spawn must be replaced by explicit prototype-safe setup.
  - Pattern: `game/objects/dungeon/dungeon.gd:78-103` - existing interactable binding and lookup model should remain the basis for Door/WallSlot integration.
  - Pattern: `game/objects/dungeon/dungeon.gd:106-145` - current room switch logic is the correct place to extend backtracking and EXIT handling.
  - API/Type: `game/objects/combat/combat_player.gd:12-18` - CombatPlayer signals and HP setup.
  - API/Type: `game/objects/combat/combat_player.gd:209-246` - existing `interact` behavior via `E` must stay compatible with doors/slots.
  - Scene: `game/objects/dungeon/dungeon.tscn:3-20` - Player script currently points at homestead player and must be swapped.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Dungeon runtime starts with exactly one room node in `Rooms`.
  - [ ] Dungeon Player uses `CombatPlayer` and can both interact and fight.
  - [ ] Moving south from a generated north room returns to the previous room without recreating it.
  - [ ] Entering EXIT triggers the run-complete flow instead of the old TODO branch.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Combat player is active in dungeon
    Tool: Bash
    Steps: Launch dungeon scene; enter first monster room; let enemy contact the player and observe HP label/logs.
    Expected: Player has HP UI and can take damage / auto-attack, confirming CombatPlayer is active.
    Evidence: .sisyphus/evidence/task-2-combat-player.txt

  Scenario: Backtracking preserves room state
    Tool: Bash
    Steps: Create first north room, enter it, then return south to START.
    Expected: START room reappears without regeneration, duplicated nodes, or repeated first-clear reward.
    Evidence: .sisyphus/evidence/task-2-backtrack.txt
  ```

  **Commit**: YES | Message: `refactor(dungeon): make runtime spawn rooms on demand` | Files: `game/objects/dungeon/dungeon.gd`, `game/objects/dungeon/dungeon.tscn`

- [x] 3. Add room clear state, north-slot reveal, and deterministic slot layout to DungeonRoom

  **What to do**: Extend `DungeonRoom` with room lifecycle state (`is_cleared`, `slots_revealed`, `reward_granted`, `was_visited`) and north-slot metadata. START should initialize as cleared and reveal slots on first visit. MONSTER/ELITE rooms should monitor enemies within the room and emit `room_cleared` when the local enemy count reaches zero for the first time. Add a dedicated north-wall slot container under each room, reveal exactly 3 slots on clear, and keep south door behavior for backtracking. The center north slot must be an active default Door; the left/right north slots must be blank `WallSlot`s until built from blueprint.
  **Must NOT do**: Do not reveal slots before START/clear conditions are met. Do not make slots appear on east/west/south walls. Do not grant repeated rewards when re-entering a room.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: moderate scene/runtime work centered in one file.
  - Skills: `[]`
  - Omitted: `['/playwright']` - Desktop game runtime, not browser UI.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 5,6,7,8 | Blocked By: 1,2

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `game/objects/dungeon/dungeon_room.gd:47-60` - extend room-level state next to existing connection and ground-item state.
  - Pattern: `game/objects/dungeon/dungeon_room.gd:63-72` - `_build_room()` is the correct construction hook for floor/label/walls plus slot container.
  - Pattern: `game/objects/dungeon/dungeon_room.gd:101-173` - current wall/door creation logic must be adapted, not bypassed.
  - Pattern: `game/objects/combat/enemy_base.gd:23-25` and `game/objects/combat/enemy_base.gd:133-143` - enemies are grouped under `enemies` and removed from that group on death; use this to detect clear state.
  - Constraint: `game/objects/dungeon/dungeon_room.gd:338-344` - room spacing is fixed by `grid_to_world`, so slot world positions must stay inside current room bounds.

  **Acceptance Criteria** (agent-executable only):
  - [ ] START room reveals 3 north slots immediately on first entry.
  - [ ] MONSTER/ELITE room emits clear once, only once, when enemies are gone.
  - [ ] Center slot is an active door; left and right slots are blank walls until blueprint build.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Start room reveals slots immediately
    Tool: Bash
    Steps: Launch dungeon scene and inspect the north wall of START.
    Expected: Exactly 3 slot interactables/visuals are visible without combat.
    Evidence: .sisyphus/evidence/task-3-start-slots.txt

  Scenario: Clear reward does not repeat on re-entry
    Tool: Bash
    Steps: Clear first monster room, leave south, then re-enter north room.
    Expected: `room_cleared` does not fire again and no second blueprint reward is granted.
    Evidence: .sisyphus/evidence/task-3-no-repeat-reward.txt
  ```

  **Commit**: YES | Message: `feat(dungeon): reveal north slots after room clear` | Files: `game/objects/dungeon/dungeon_room.gd`

- [x] 4. Introduce dedicated Door and WallSlot nodes/scenes

  **What to do**: Create reusable `Door` and `WallSlot` scene/script pairs under `game/objects/dungeon/`. Both must extend `Area2D`, expose slot metadata (`slot_index`, `grid_pos`, `target_grid_pos`, `is_blank`, `target_room_type`), and separate visual state from interaction state. `Door` must support default-door and overridden-door visuals/types. `WallSlot` must support blank-wall, highlighted, and built-door-capable states. Both must integrate with the player's existing `register_interactable` / `unregister_interactable` flow and provide deterministic highlight APIs for mouse hover and keyboard selection.
  **Must NOT do**: Do not keep north-slot logic as anonymous raw `Area2D`s inside `DungeonRoom`. Do not encode slot behavior only in names/strings. Do not add scene types outside `game/objects/dungeon/`.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` - Reason: UI/scene node composition plus interaction affordance.
  - Skills: `[]`
  - Omitted: `['/frontend-ui-ux']` - Godot scene work, not web frontend.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 5,6,7 | Blocked By: 1

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `game/objects/dungeon/dungeon_room.gd:197-223` - current doors are raw `Area2D` + visual blocks; split this into reusable nodes.
  - API/Type: `game/objects/combat/combat_player.gd:249-255` - interactables must stay as `Area2D` so the player interaction list works unchanged.
  - Pattern: `game/objects/dungeon/dungeon.gd:78-88` - body enter/exit registration model to preserve.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Both `Door` and `WallSlot` are reusable `Area2D`-based components.
  - [ ] Both expose enough metadata so `Dungeon` can resolve slot action without string parsing.
  - [ ] Both support visible selection/highlight state for keyboard fallback.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Slot components register as interactables
    Tool: Bash
    Steps: Walk near a revealed door slot and blank wall slot.
    Expected: Player interaction prompt appears for both and no raw-area lookup errors occur.
    Evidence: .sisyphus/evidence/task-4-slot-interactables.txt

  Scenario: Selection highlight is controllable
    Tool: Bash
    Steps: Trigger slot highlight state from keyboard selection flow or temporary debug input.
    Expected: Selected slot has a distinct visual state and unselected slots revert correctly.
    Evidence: .sisyphus/evidence/task-4-slot-highlight.txt
  ```

  **Commit**: YES | Message: `feat(dungeon): add reusable door and wall slot nodes` | Files: `game/objects/dungeon/door.gd`, `game/objects/dungeon/door.tscn`, `game/objects/dungeon/wall_slot.gd`, `game/objects/dungeon/wall_slot.tscn`

- [x] 5. Intercept blueprint drag/drop and resolve world-slot targeting

  **What to do**: Extend the inventory-to-world drop path so blueprint items do not immediately become ground items when released outside the inventory panel in dungeon context. Instead, while dragging a blueprint, detect overlap with visible Door/WallSlot targets in the current room and forward a structured placement request to `Dungeon`. Non-blueprint items must keep the existing ground-drop path unchanged. Preserve existing inventory rotation and preview behavior inside the panel. If no valid slot is under the cursor, releasing a blueprint should cancel placement and restore it to inventory rather than dropping it on the floor.
  **Must NOT do**: Do not break ordinary item dropping from `item_dropped_from_inventory`. Do not reimplement the entire inventory drag system. Do not permit blueprint use on hidden/non-current rooms.

  **Recommended Agent Profile**:
  - Category: `deep` - Reason: cross-system interaction between UI drag state and world runtime.
  - Skills: `[]`
  - Omitted: `['/review-work']` - This is implementation planning, not post-implementation review.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 6,7,8 | Blocked By: 2,3,4

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `game/inventory/inventory_ui.gd:315-347` - input flow for dragging/open/rotation.
  - Pattern: `game/inventory/inventory_ui.gd:370-381` - drop release logic currently decides panel-inside vs outside.
  - Anti-pattern to branch from: `game/inventory/inventory_ui.gd:508-512` - current outside-panel release always emits ground-drop signal.
  - Contract: `game/data/items.json:352-406` - blueprint item definitions and `blueprint.room_type` payload already exist.
  - Existing dungeon drop path: `game/objects/dungeon/dungeon.gd:212-219` - keep as fallback for non-blueprint items.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Dragging a non-blueprint outside inventory still drops it as ground item in the current room.
  - [ ] Dragging a blueprint over a valid Door/WallSlot calls dungeon placement logic instead of ground drop.
  - [ ] Dragging a blueprint outside inventory with no valid slot restores the item to inventory.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Blueprint release targets slot instead of ground
    Tool: Bash
    Steps: Open inventory with `T`; drag `bp_shop_room` over a visible blank WallSlot and release.
    Expected: Blueprint is consumed by slot placement flow; no ground item visual is spawned.
    Evidence: .sisyphus/evidence/task-5-blueprint-targeting.txt

  Scenario: Non-blueprint release still drops to floor
    Tool: Bash
    Steps: Drag a potion outside the inventory panel while standing in a room.
    Expected: Existing ground drop path still executes and the item appears as a ground pickup.
    Evidence: .sisyphus/evidence/task-5-ground-drop.txt
  ```

  **Commit**: YES | Message: `feat(inventory): route blueprints to dungeon slots` | Files: `game/inventory/inventory_ui.gd`, `game/objects/dungeon/dungeon.gd`

- [x] 6. Implement blueprint override/create resolution and room materialization

  **What to do**: Add the authoritative placement handler in `Dungeon` that receives blueprint item + targeted Door/WallSlot metadata, validates room type, consumes the blueprint, and either (a) overrides the center default door's target room type before entering it or (b) creates a new left/right north room from a blank slot and converts that slot into an active door. Target room types for this phase are only `MONSTER`, `ELITE`, and `SHOP`. Exclude `TREASURE` from both reward generation and placement unless a safe placeholder enum is explicitly added. Room creation must update generator state, `connections`, `door_areas`, `_room_nodes`, minimap state if applicable, and current room north-wall visuals.
  **Must NOT do**: Do not allow multiple rooms on the same slot. Do not consume blueprint on invalid placement. Do not allow blueprint placement onto south/backtracking doors.

  **Recommended Agent Profile**:
  - Category: `deep` - Reason: authoritative runtime rule enforcement and data synchronization.
  - Skills: `[]`
  - Omitted: `['/playwright']` - Not browser-based.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: 7,8 | Blocked By: 1,2,3,4,5

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `game/objects/dungeon/dungeon.gd:91-103` - central interaction dispatch point.
  - Pattern: `game/objects/dungeon/dungeon.gd:106-145` - room transition should remain the single movement path after placement.
  - Data contract: `game/data/items.json:352-392` - allowed blueprint room types for this phase.
  - Guardrail source: `game/data/items.json:394-406` + `game/objects/dungeon/dungeon_room.gd:8-14` - `TREASURE` blueprint exists but enum support does not.
  - Pattern: `game/objects/dungeon/dungeon_room.gd:119-173` - wall/door geometry expectations for turning a blank slot into a usable door.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Overriding the center door changes the target room type before entry.
  - [ ] Building on left/right blank slot creates a new room and converts the slot to an enterable door.
  - [ ] Invalid blueprint types or invalid targets do not consume the item.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Override center default door
    Tool: Bash
    Steps: In START, drag `bp_elite_room` onto the center north door, then enter it.
    Expected: The entered room is typed/rendered as ELITE instead of default MONSTER.
    Evidence: .sisyphus/evidence/task-6-override-door.txt

  Scenario: Create new room from blank slot
    Tool: Bash
    Steps: Drag `bp_shop_room` onto the left blank WallSlot, then interact with the new door.
    Expected: A SHOP room node is created at the correct target grid position, and the slot becomes traversable.
    Evidence: .sisyphus/evidence/task-6-create-door.txt
  ```

  **Commit**: YES | Message: `feat(dungeon): apply blueprints to override or create rooms` | Files: `game/objects/dungeon/dungeon.gd`, `game/objects/dungeon/dungeon_generator.gd`, `game/objects/dungeon/dungeon_room.gd`

- [x] 7. Add fixed reward loop and room-type-based spawn hooks

  **What to do**: On first clear of a combat room, add exactly one random blueprint from the allowed reward pool to player inventory. START gives no reward. MONSTER and ELITE should both be able to spawn enemies; SHOP should not. Ensure the reward is granted after clear, before or alongside slot reveal, and logged deterministically. Seed the player with a small prototype-safe starting blueprint set if required to make the first room choice testable from START without external setup.
  **Must NOT do**: Do not build rarity tables, weighted loot balancing, treasure rooms, or a vendor system. Do not grant rewards from SHOP/EXIT/START.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: bounded feature once runtime hooks exist.
  - Skills: `[]`
  - Omitted: `['/git-master']` - No git operation in planning/execution instructions.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 8 | Blocked By: 2,3,5,6

  **References** (executor has NO interview context - be exhaustive):
  - Existing startup item seeding to replace: `game/objects/dungeon/dungeon.gd:65-72`.
  - Item definitions: `game/data/items.json:352-392` - allowed blueprint reward pool.
  - Guardrail exclusion: `game/data/items.json:394-406` - `bp_treasure_room` must stay out of pool.
  - Inventory setup: `game/objects/dungeon/dungeon.gd:52-57` - player inventory/UI already exists and should receive rewards directly.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Clearing a MONSTER or ELITE room grants exactly one allowed blueprint.
  - [ ] SHOP, START, and EXIT do not grant blueprint rewards.
  - [ ] Reward grant occurs only once per room.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Combat room grants one blueprint
    Tool: Bash
    Steps: Clear a MONSTER room and inspect inventory contents before/after.
    Expected: Inventory gains exactly one of `bp_monster_room`, `bp_elite_room`, or `bp_shop_room`.
    Evidence: .sisyphus/evidence/task-7-blueprint-reward.txt

  Scenario: Non-combat room grants nothing
    Tool: Bash
    Steps: Enter SHOP or EXIT and inspect inventory delta.
    Expected: No reward is added on room entry or revisit.
    Evidence: .sisyphus/evidence/task-7-no-shop-reward.txt
  ```

  **Commit**: YES | Message: `feat(dungeon): add blueprint rewards for cleared rooms` | Files: `game/objects/dungeon/dungeon.gd`, `game/objects/dungeon/dungeon_room.gd`

- [x] 8. Implement keyboard fallback for slot selection and blueprint application

  **What to do**: When the current room has visible north slots, pressing `Tab` must cycle among the visible `Door`/`WallSlot` targets; the selected slot must highlight. Pressing existing `interact` (`E`) while a slot is selected should either apply the first compatible blueprint found in inventory or open a minimal deterministic selection path if multiple blueprint types exist. Keep the fallback intentionally small: no free cursor, no radial menu, no remapping changes. Document the exact precedence order for auto-selection (e.g. inventory order or room-type priority) in code comments and QA logs.
  **Must NOT do**: Do not add a new input action to `project.godot`. Do not require mouse hover for keyboard mode. Do not build full controller support in this phase.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: small but cross-cutting input/selection feature.
  - Skills: `[]`
  - Omitted: `['/dev-browser']` - No browser automation needed.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: Final Verification only | Blocked By: 2,3,4,5,6,7

  **References** (executor has NO interview context - be exhaustive):
  - Existing input actions: `project.godot:71-95` - `interact` is `E`, `inventory` is `T`, `dropitem` is `Q`; no new action should be added.
  - Interaction path: `game/objects/combat/combat_player.gd:209-246` - `E` already emits interaction for nearby `Area2D` targets.
  - Inventory keyboard precedent: `game/inventory/inventory_ui.gd:325-347` - current inventory key handling patterns.
  - Slot highlight requirement source: Task 4 reusable `Door` / `WallSlot` nodes.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `Tab` cycles only visible slots in the current room.
  - [ ] `E` applies a compatible blueprint to the selected slot without mouse drag.
  - [ ] If no compatible blueprint exists, the UI/log reports that state and consumes nothing.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Cycle visible slots with keyboard
    Tool: Bash
    Steps: Enter a room with visible north slots; press Tab repeatedly.
    Expected: Selection advances through visible slots only and wraps around after the last slot.
    Evidence: .sisyphus/evidence/task-8-tab-cycle.txt

  Scenario: Keyboard apply fails safely without blueprint
    Tool: Bash
    Steps: Empty inventory of compatible blueprints, select a slot with Tab, press E.
    Expected: No slot change occurs, no item is consumed, and feedback indicates no valid blueprint.
    Evidence: .sisyphus/evidence/task-8-no-blueprint.txt
  ```

  **Commit**: YES | Message: `feat(dungeon): add keyboard fallback for slot blueprints` | Files: `game/objects/dungeon/dungeon.gd`, `game/objects/dungeon/dungeon_room.gd`, `game/inventory/inventory_ui.gd`

## Final Verification Wave (MANDATORY — after ALL implementation tasks)
> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.
- [x] F1. Plan Compliance Audit — oracle
- [x] F2. Code Quality Review — unspecified-high
- [x] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [x] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit after Task 2 to lock the runtime conversion baseline.
- Commit after Task 4 to lock reusable Door/WallSlot primitives.
- Commit after Task 6 to lock blueprint placement behavior.
- Commit after Task 8 only after the full manual QA matrix passes.

## Success Criteria
- The dungeon no longer pre-generates a random full graph at startup.
- The player's progression choice is expressed through visible north-wall slots and blueprint use.
- Existing inventory drag/drop is preserved for non-blueprint items.
- The prototype is fully playable through START → chosen rooms → EXIT within one run.
- No excluded systems (mutation/pitfall/mimic/altar/save/balance/polish) leak into the implementation.
