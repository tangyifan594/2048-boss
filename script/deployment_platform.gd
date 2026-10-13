class_name DeploymentPlatform
extends Control


# ==================== 对外信号 ====================

# 一个棋盘角色成功放入出战槽位时发出。
signal archer_deployed(tile: ArcherTile, slot_index: int)

# 玩家点击一键出战按钮时发出，由Main从棋盘选择最高等级角色。
signal auto_deploy_requested

# 玩家点击锁定槽位时发出，由Main检查并支付金币。
signal slot_unlock_requested(slot_index: int, cost: int)


# ==================== 场景资源 ====================

const BATTLE_ARCHER_SCENE := preload("res://scene/BattleArcher.tscn")


# ==================== 节点与数据 ====================

@onready var slots: Array[Control] = [$Slot1, $Slot2, $Slot3]
@onready var auto_deploy_button: Button = $AutoDeployButton
@onready var slot_2_unlock_button: Button = $Slot2UnlockButton
@onready var slot_3_unlock_button: Button = $Slot3UnlockButton

# 三个槽位的解锁价格；第一格开局免费。
@export var slot_unlock_costs: Array[int] = [0, 20, 50]

var deployed_tiles: Array[ArcherTile] = []
var deployed_archers: Array[BattleArcher] = []
var unlocked_slots: Array[bool] = [true, false, false]


# ==================== 初始化 ====================

# 功能：建立三个空的出战槽位数据。
func _ready() -> void:
	deployed_tiles.resize(slots.size())
	deployed_tiles.fill(null)
	deployed_archers.resize(slots.size())
	deployed_archers.fill(null)
	auto_deploy_button.pressed.connect(_on_auto_deploy_button_pressed)
	slot_2_unlock_button.pressed.connect(_on_unlock_button_pressed.bind(1))
	slot_3_unlock_button.pressed.connect(_on_unlock_button_pressed.bind(2))
	refresh_unlock_buttons()


# 功能：把一键出战请求交给Main，避免出战台直接读取棋盘内部数据。
func _on_auto_deploy_button_pressed() -> void:
	auto_deploy_requested.emit()


# ==================== 出战位解锁 ====================

# 功能：把指定槽位和价格交给Main处理购买。
func _on_unlock_button_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= slot_unlock_costs.size():
		return

	slot_unlock_requested.emit(slot_index, maxi(slot_unlock_costs[slot_index], 0))


# 功能：成功付款后解锁本局中的指定槽位。
func unlock_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= unlocked_slots.size():
		return false

	if unlocked_slots[slot_index]:
		return false

	unlocked_slots[slot_index] = true
	refresh_unlock_buttons()
	return true


# 功能：检查槽位是否已经解锁。
func is_slot_unlocked(slot_index: int) -> bool:
	return (
		slot_index >= 0
		and slot_index < unlocked_slots.size()
		and unlocked_slots[slot_index]
	)


# 功能：根据解锁状态显示或隐藏锁和价格。
func refresh_unlock_buttons() -> void:
	slot_2_unlock_button.visible = not is_slot_unlocked(1)
	slot_3_unlock_button.visible = not is_slot_unlocked(2)
	var slot_2_cost_label := $Slot2UnlockButton/Price/CostLabel as Label
	var slot_3_cost_label := $Slot3UnlockButton/Price/CostLabel as Label
	slot_2_cost_label.text = str(slot_unlock_costs[1])
	slot_3_cost_label.text = str(slot_unlock_costs[2])


# ==================== 接收棋盘拖动 ====================

# 功能：只有拖着未出战的棋盘角色，并指向空槽时才允许放下。
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false

	if data.get("type", "") != "archer_tile":
		return false

	var tile := data.get("tile") as ArcherTile

	if tile == null or not is_instance_valid(tile) or tile.deployed:
		return false

	return find_slot_at_position(at_position) >= 0


# 功能：把棋盘角色安排到鼠标指向的空槽，并生成战斗形态。
func _drop_data(at_position: Vector2, data: Variant) -> void:
	var slot_index := find_slot_at_position(at_position)

	if slot_index < 0:
		return

	var tile := data.get("tile") as ArcherTile

	if tile == null or not is_instance_valid(tile):
		return

	deploy_tile_to_slot(tile, slot_index)


# ==================== 一键出战 ====================

# 功能：按传入顺序把角色填入空槽；Main会提前按等级从高到低排序。
func auto_deploy_tiles(tiles: Array[ArcherTile]) -> void:
	for tile in tiles:
		var empty_slot_index := find_first_empty_slot()

		if empty_slot_index < 0:
			return

		if tile == null or not is_instance_valid(tile) or tile.deployed:
			continue

		deploy_tile_to_slot(tile, empty_slot_index)


# 功能：把一个棋盘角色放进指定空槽，并创建对应的战斗射手。
func deploy_tile_to_slot(tile: ArcherTile, slot_index: int) -> bool:
	if tile == null or not is_instance_valid(tile) or tile.deployed:
		return false

	if slot_index < 0 or slot_index >= slots.size():
		return false

	if not is_slot_unlocked(slot_index):
		return false

	if deployed_tiles[slot_index] != null:
		return false

	var battle_archer := BATTLE_ARCHER_SCENE.instantiate() as BattleArcher
	var slot := slots[slot_index]

	slot.add_child(battle_archer)
	battle_archer.position = slot.size * 0.5
	battle_archer.setup_from_tile(tile.value)

	deployed_tiles[slot_index] = tile
	deployed_archers[slot_index] = battle_archer
	tile.set_deployed(true)
	archer_deployed.emit(tile, slot_index)
	return true


# 功能：返回第一个空出战槽，没有空位时返回-1。
func find_first_empty_slot() -> int:
	for slot_index in range(slots.size()):
		if is_slot_unlocked(slot_index) and deployed_tiles[slot_index] == null:
			return slot_index

	return -1


# 功能：波次期间禁用一键出战按钮，防止战斗中修改阵容。
func set_deployment_locked(is_locked: bool) -> void:
	auto_deploy_button.disabled = is_locked
	slot_2_unlock_button.disabled = is_locked
	slot_3_unlock_button.disabled = is_locked
	auto_deploy_button.modulate = (
		Color(0.55, 0.55, 0.55, 0.85) if is_locked else Color.WHITE
	)


# 功能：空阵容尝试开战时，让整个出战台短暂闪红。
func play_empty_deployment_feedback() -> void:
	self_modulate = Color(1.0, 0.35, 0.28, 1.0)
	var feedback_tween := create_tween()
	feedback_tween.tween_property(self, "self_modulate", Color.WHITE, 0.32)


# ==================== 拖回棋盘 ====================

# 功能：从已有射手的槽位开始拖动，并提供跟随鼠标的射手预览。
func _get_drag_data(at_position: Vector2) -> Variant:
	var slot_index := find_occupied_slot_at_position(at_position)

	if slot_index < 0:
		return null

	var tile := deployed_tiles[slot_index]
	var battle_archer := deployed_archers[slot_index]

	if tile == null or not is_instance_valid(tile):
		return null

	if battle_archer == null or not is_instance_valid(battle_archer):
		return null

	var board_node := tile.get_parent().get_parent() as Board2048

	if board_node == null or board_node.is_battle_locked:
		return null

	set_drag_preview(create_archer_drag_preview(battle_archer))

	return {
		"type": "deployed_archer",
		"platform": self,
		"slot_index": slot_index,
		"tile": tile,
	}


# 功能：创建撤回射手时跟随鼠标的画面副本。
func create_archer_drag_preview(battle_archer: BattleArcher) -> Control:
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(92.0, 92.0)
	preview.size = preview.custom_minimum_size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)

	var sprite_copy := battle_archer.animated_sprite.duplicate() as AnimatedSprite2D
	sprite_copy.position = preview.size * 0.5
	preview.add_child(sprite_copy)
	return preview


# 功能：把指定槽位的射手撤回棋盘，并恢复原棋子的操作状态。
func return_archer_to_board(slot_index: int) -> bool:
	if not can_return_slot(slot_index):
		return false

	var tile := deployed_tiles[slot_index]
	var battle_archer := deployed_archers[slot_index]

	deployed_tiles[slot_index] = null
	deployed_archers[slot_index] = null
	tile.set_deployed(false)
	battle_archer.queue_free()
	return true


# 功能：检查一个出战槽是否包含可以撤回的射手。
func can_return_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false

	var tile := deployed_tiles[slot_index]
	var battle_archer := deployed_archers[slot_index]
	return (
		tile != null
		and is_instance_valid(tile)
		and battle_archer != null
		and is_instance_valid(battle_archer)
	)


# 功能：找出鼠标当前指向的空槽；没有则返回-1。
func find_slot_at_position(at_position: Vector2) -> int:
	for slot_index in range(slots.size()):
		if not is_slot_unlocked(slot_index):
			continue

		if deployed_tiles[slot_index] != null:
			continue

		var slot := slots[slot_index]
		var slot_rect := Rect2(slot.position, slot.size)

		if slot_rect.has_point(at_position):
			return slot_index

	return -1


# 功能：找出鼠标指向的已有射手槽位。
func find_occupied_slot_at_position(at_position: Vector2) -> int:
	for slot_index in range(slots.size()):
		if not can_return_slot(slot_index):
			continue

		var slot := slots[slot_index]
		var slot_rect := Rect2(slot.position, slot.size)

		if slot_rect.has_point(at_position):
			return slot_index

	return -1


# ==================== 波次结束归队 ====================

# 功能：清空全部出战槽，并让棋盘角色恢复正常显示和操作。
func clear_deployments() -> void:
	for slot_index in range(slots.size()):
		var tile := deployed_tiles[slot_index]
		var battle_archer := deployed_archers[slot_index]

		if tile != null and is_instance_valid(tile):
			tile.set_deployed(false)

		if battle_archer != null and is_instance_valid(battle_archer):
			battle_archer.queue_free()

		deployed_tiles[slot_index] = null
		deployed_archers[slot_index] = null


# 功能：返回当前有效的全部战斗射手，供自动攻击系统使用。
func get_deployed_archers() -> Array[BattleArcher]:
	var result: Array[BattleArcher] = []

	for battle_archer in deployed_archers:
		if battle_archer != null and is_instance_valid(battle_archer):
			result.append(battle_archer)

	return result
