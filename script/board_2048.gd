class_name Board2048
extends Control


# ==================== 对外信号 ====================

# 通知道具栏交换模式是否开启。
signal swap_mode_changed(is_active: bool)

# 两个角色完成交换后发出；以后在这里确认扣除金币。
signal swap_completed

# 玩家按下有效方向键时，请求Main检查并支付滑动金币。
signal slide_requested(direction: Vector2i)


# ==================== 棋盘配置 ====================

# 棋盘为4行4列。
const BOARD_SIZE := 4

# 第一行第一列角色的画面位置。
const GRID_ORIGIN := Vector2(55, 66)

# 相邻两列和相邻两行之间的距离。
const CELL_STEP := Vector2(114, 110)

# 棋盘中使用的角色场景。
const TILE_SCENE := preload("res://scene/ArcherTile.tscn")

# 角色滑动到目标格子的时间。
const MOVE_DURATION := 0.14

# 合并和生成反馈播放完之前，继续锁定输入的时间。
const FEEDBACK_DURATION := 0.12


# 保存一个角色及其本次移动的目标位置。
class TileMoveOperation:
	var tile: ArcherTile
	var target_position: Vector2

	func _init(new_tile: ArcherTile, new_target_position: Vector2) -> void:
		tile = new_tile
		target_position = new_target_position


# 保存一次合并中保留的角色和被消耗的角色。
class TileMergeOperation:
	var target_tile: ArcherTile
	var source_tile: ArcherTile

	func _init(new_target_tile: ArcherTile, new_source_tile: ArcherTile) -> void:
		target_tile = new_target_tile
		source_tile = new_source_tile


# 保存一组角色；source_tile为空表示这组角色没有发生合并。
class TileGroup:
	var target_tile: ArcherTile
	var source_tile: ArcherTile

	func _init(new_target_tile: ArcherTile, new_source_tile: ArcherTile = null) -> void:
		target_tile = new_target_tile
		source_tile = new_source_tile


# ==================== 节点与数据 ====================

# 所有角色节点都放在TileLayer下面。
@onready var tile_layer: Control = $TileLayer

# 有效滑动开始时播放一次滑动音效。
@onready var slide_sound: AudioStreamPlayer = $SlideSound

# 保存4×4棋盘中的角色；空格使用null表示。
var board: Array = []

# 动画播放期间锁定方向键，防止连续输入破坏棋盘数据。
var is_animating := false

# 波次进行期间锁定滑动、交换和拖动出战。
var is_battle_locked := false

# 保存当前回合需要播放的全部移动和合并。
var pending_moves: Array[TileMoveOperation] = []
var pending_merges: Array[TileMergeOperation] = []

# 是否正在等待玩家选择两个需要交换的角色。
var is_swap_mode := false

# 交换模式中第一个被选中的角色。
var first_swap_tile: ArcherTile = null


# ==================== 初始化 ====================

# 功能：创建空棋盘，并随机生成两个初始角色。
func _ready() -> void:
	create_empty_board()

	var first_tile := spawn_random_tile()
	var second_tile := spawn_random_tile()

	if first_tile != null:
		first_tile.play_spawn_animation()

	if second_tile != null:
		second_tile.play_spawn_animation()


# ==================== 棋盘数据 ====================

# 功能：建立4×4的空棋盘数据。
func create_empty_board() -> void:
	board.clear()

	for row in range(BOARD_SIZE):
		var row_data: Array = []
		row_data.resize(BOARD_SIZE)
		row_data.fill(null)
		board.append(row_data)


# ==================== 放置位置 ====================

# 功能：把棋盘中的行列坐标换算成角色的画面位置。
func grid_to_position(row: int, column: int) -> Vector2:
	return GRID_ORIGIN + Vector2(
		column * CELL_STEP.x,
		row * CELL_STEP.y
	)


# 功能：在指定行列创建角色，并返回新角色。
func spawn_tile(row: int, column: int, value: int = 2) -> ArcherTile:
	if row < 0 or row >= BOARD_SIZE:
		return null

	if column < 0 or column >= BOARD_SIZE:
		return null

	if board[row][column] != null:
		return null

	var tile := TILE_SCENE.instantiate() as ArcherTile

	tile_layer.add_child(tile)
	tile.position = grid_to_position(row, column)
	tile.set_value(value)
	tile.tile_clicked.connect(_on_tile_clicked)

	board[row][column] = tile
	return tile


# ==================== 随机生成 ====================

# 功能：取得当前棋盘中所有空格的行列坐标。
func get_empty_cells() -> Array[Vector2i]:
	var empty_cells: Array[Vector2i] = []

	for row in range(BOARD_SIZE):
		for column in range(BOARD_SIZE):
			if board[row][column] == null:
				empty_cells.append(Vector2i(column, row))

	return empty_cells


# 功能：随机选择一个空格，并返回新生成的数值2角色。
func spawn_random_tile() -> ArcherTile:
	var empty_cells := get_empty_cells()

	if empty_cells.is_empty():
		return null

	var selected_cell: Vector2i = empty_cells.pick_random()

	return spawn_tile(
		selected_cell.y,
		selected_cell.x,
		2
	)


# ==================== 移动与合并（上、下、左、右） ====================

# 功能：优先读取方向键，避免UI按钮获得焦点后截走棋盘输入。
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey

	if key_event.echo:
		return

	if event.is_action_pressed("ui_cancel") and is_swap_mode:
		cancel_swap_mode()
		get_viewport().set_input_as_handled()
		return

	var direction := Vector2i.ZERO

	if event.is_action_pressed("ui_left"):
		direction = Vector2i.LEFT
	elif event.is_action_pressed("ui_right"):
		direction = Vector2i.RIGHT
	elif event.is_action_pressed("ui_up"):
		direction = Vector2i.UP
	elif event.is_action_pressed("ui_down"):
		direction = Vector2i.DOWN

	if direction == Vector2i.ZERO:
		return

	# 方向键属于棋盘，即使动画中不能移动，也不交给UI导航。
	get_viewport().set_input_as_handled()

	if is_animating or is_swap_mode or is_battle_locked:
		return

	slide_requested.emit(direction)


# 功能：执行一次完整回合；只有移动或合并成功才生成新角色。
# 返回值以后可用于决定是否扣除滑动次数或金币。
func perform_turn(direction: Vector2i) -> bool:
	if is_animating or is_battle_locked or has_deployed_tiles():
		return false

	pending_moves.clear()
	pending_merges.clear()

	if not move_board(direction):
		pending_moves.clear()
		pending_merges.clear()
		return false

	is_animating = true
	slide_sound.play()
	play_move_animations()
	return true


# 功能：让本回合的所有角色同时滑动到目标格子。
func play_move_animations() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	for operation in pending_moves:
		tween.tween_property(
			operation.tile,
			"position",
			operation.target_position,
			MOVE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.finished.connect(finish_turn)


# 功能：滑动结束后执行数值合并、生成新角色和反馈动画。
func finish_turn() -> void:
	for operation in pending_merges:
		if not is_instance_valid(operation.target_tile):
			continue

		if not is_instance_valid(operation.source_tile):
			continue

		operation.target_tile.set_value(operation.target_tile.value * 2)
		operation.source_tile.queue_free()
		operation.target_tile.play_merge_animation()

	pending_moves.clear()
	pending_merges.clear()

	var new_tile := spawn_random_tile()

	if new_tile != null:
		new_tile.play_spawn_animation()

	var feedback_tween := create_tween()
	feedback_tween.tween_interval(FEEDBACK_DURATION)
	feedback_tween.finished.connect(unlock_input)


# 功能：全部反馈播放结束后，重新接受方向键输入。
func unlock_input() -> void:
	is_animating = false


# 功能：按照指定方向处理棋盘中的4行或4列。
func move_board(direction: Vector2i) -> bool:
	var moved := false

	for line_index in range(BOARD_SIZE):
		var coordinates := get_line_coordinates(line_index, direction)

		if coordinates.size() != BOARD_SIZE:
			return false

		if process_line(coordinates):
			moved = true

	return moved


# 功能：根据移动方向，取得一行或一列的读取顺序。
# 坐标中的x代表列，y代表行；数组第一个坐标始终靠近移动方向。
func get_line_coordinates(
	line_index: int,
	direction: Vector2i
) -> Array[Vector2i]:
	var coordinates: Array[Vector2i] = []

	for offset in range(BOARD_SIZE):
		var coordinate := Vector2i.ZERO

		if direction == Vector2i.LEFT:
			coordinate = Vector2i(offset, line_index)
		elif direction == Vector2i.RIGHT:
			coordinate = Vector2i(BOARD_SIZE - 1 - offset, line_index)
		elif direction == Vector2i.UP:
			coordinate = Vector2i(line_index, offset)
		elif direction == Vector2i.DOWN:
			coordinate = Vector2i(line_index, BOARD_SIZE - 1 - offset)
		else:
			return coordinates

		coordinates.append(coordinate)

	return coordinates


# 功能：规划一行或一列的“收集、合并、写回和动画”。
func process_line(coordinates: Array[Vector2i]) -> bool:
	var original_tiles := collect_line_tiles(coordinates)

	if original_tiles.is_empty():
		return false

	var tile_groups := group_adjacent_tiles(original_tiles)
	var merged := tile_groups.size() != original_tiles.size()
	var repositioned := false

	clear_line(coordinates)

	for group_index in range(tile_groups.size()):
		var tile_group := tile_groups[group_index]
		var coordinate := coordinates[group_index]
		var target_position := grid_to_position(coordinate.y, coordinate.x)

		board[coordinate.y][coordinate.x] = tile_group.target_tile
		pending_moves.append(
			TileMoveOperation.new(tile_group.target_tile, target_position)
		)

		if tile_group.target_tile.position != target_position:
			repositioned = true

		if tile_group.source_tile != null:
			pending_moves.append(
				TileMoveOperation.new(tile_group.source_tile, target_position)
			)
			pending_merges.append(
				TileMergeOperation.new(
					tile_group.target_tile,
					tile_group.source_tile
				)
			)

	return merged or repositioned


# 功能：按移动方向收集一行或一列中的所有角色，跳过空格。
func collect_line_tiles(
	coordinates: Array[Vector2i]
) -> Array[ArcherTile]:
	var tiles: Array[ArcherTile] = []

	for coordinate in coordinates:
		var tile := board[coordinate.y][coordinate.x] as ArcherTile

		if tile != null:
			tiles.append(tile)

	return tiles


# 功能：按照正式2048规则把相邻角色整理成待放置的组。
# 每次只组成一对，因此新角色不会在同一次移动中再次合并。
func group_adjacent_tiles(
	tiles: Array[ArcherTile]
) -> Array[TileGroup]:
	var groups: Array[TileGroup] = []
	var tile_index := 0

	while tile_index < tiles.size():
		var current_tile := tiles[tile_index]

		if tile_index + 1 < tiles.size():
			var next_tile := tiles[tile_index + 1]

			if current_tile.value == next_tile.value:
				groups.append(TileGroup.new(current_tile, next_tile))
				tile_index += 2
				continue

		groups.append(TileGroup.new(current_tile))
		tile_index += 1

	return groups


# 功能：清空一行或一列原来的棋盘数据。
func clear_line(coordinates: Array[Vector2i]) -> void:
	for coordinate in coordinates:
		board[coordinate.y][coordinate.x] = null


# ==================== 交换道具 ====================

# 功能：进入交换模式；如果已经在交换模式中，再次调用会取消。
func begin_swap_mode() -> void:
	if is_animating or is_battle_locked or has_deployed_tiles():
		return

	if is_swap_mode:
		cancel_swap_mode()
		return

	is_swap_mode = true
	first_swap_tile = null
	swap_mode_changed.emit(true)


# 功能：取消交换模式，并清除已经选中的角色。
func cancel_swap_mode() -> void:
	if first_swap_tile != null and is_instance_valid(first_swap_tile):
		first_swap_tile.set_selected(false)

	first_swap_tile = null
	is_swap_mode = false
	swap_mode_changed.emit(false)


# 功能：处理交换模式中的角色点击。
func _on_tile_clicked(tile: ArcherTile) -> void:
	if not is_swap_mode or is_animating:
		return

	if first_swap_tile == null:
		first_swap_tile = tile
		first_swap_tile.set_selected(true)
		return

	if tile == first_swap_tile:
		first_swap_tile.set_selected(false)
		first_swap_tile = null
		return

	perform_swap(first_swap_tile, tile)


# 功能：交换两个角色在棋盘数据中的位置，并播放互换动画。
func perform_swap(first_tile: ArcherTile, second_tile: ArcherTile) -> void:
	var first_cell := find_tile_cell(first_tile)
	var second_cell := find_tile_cell(second_tile)

	if first_cell.x < 0 or second_cell.x < 0:
		cancel_swap_mode()
		return

	is_animating = true
	first_tile.set_selected(false)
	first_swap_tile = null
	is_swap_mode = false
	swap_mode_changed.emit(false)

	board[first_cell.y][first_cell.x] = second_tile
	board[second_cell.y][second_cell.x] = first_tile

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		first_tile,
		"position",
		grid_to_position(second_cell.y, second_cell.x),
		MOVE_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		second_tile,
		"position",
		grid_to_position(first_cell.y, first_cell.x),
		MOVE_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_finish_swap)


# 功能：根据角色节点查找它当前所在的行列。
func find_tile_cell(tile: ArcherTile) -> Vector2i:
	for row in range(BOARD_SIZE):
		for column in range(BOARD_SIZE):
			if board[row][column] == tile:
				return Vector2i(column, row)

	return Vector2i(-1, -1)


# 功能：交换动画完成后恢复输入，并通知外部交换已经完成。
func _finish_swap() -> void:
	is_animating = false
	swap_completed.emit()


# ==================== 出战拖动 ====================

# 功能：允许把出战台上的射手拖回棋盘；它会回到原来的2048格子。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return can_accept_archer_return(data)


# 功能：在棋盘范围放开鼠标后，通知出战台撤回对应射手。
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	accept_archer_return(data)


# 功能：检查拖动数据是否来自有效的出战槽位。
func can_accept_archer_return(data: Variant) -> bool:
	if is_animating or is_swap_mode or is_battle_locked:
		return false

	if not data is Dictionary:
		return false

	if data.get("type", "") != "deployed_archer":
		return false

	var platform := data.get("platform") as DeploymentPlatform
	var tile := data.get("tile") as ArcherTile
	var slot_index: int = int(data.get("slot_index", -1))

	if platform == null or tile == null or not is_instance_valid(tile):
		return false

	return tile.deployed and platform.can_return_slot(slot_index)


# 功能：执行撤回；棋盘数据不变，只恢复原格子中的角色。
func accept_archer_return(data: Variant) -> void:
	if not can_accept_archer_return(data):
		return

	var platform := data.get("platform") as DeploymentPlatform
	var slot_index: int = int(data.get("slot_index", -1))
	platform.return_archer_to_board(slot_index)

# 功能：判断指定角色当前能否从棋盘拖到出战台。
func can_start_tile_drag(tile: ArcherTile) -> bool:
	if is_animating or is_swap_mode or is_battle_locked:
		return false

	if tile == null or tile.deployed:
		return false

	return find_tile_cell(tile).x >= 0


# 功能：波次开始时锁定棋盘，波次结束后恢复操作。
func set_battle_locked(is_locked: bool) -> void:
	is_battle_locked = is_locked

	if is_battle_locked and is_swap_mode:
		cancel_swap_mode()


# 功能：检查棋盘是否已有角色处于出战状态。
func has_deployed_tiles() -> bool:
	for row in range(BOARD_SIZE):
		for column in range(BOARD_SIZE):
			var tile := board[row][column] as ArcherTile

			if tile != null and tile.deployed:
				return true

	return false


# 功能：取得所有未出战角色，并按数值从高到低排列，供一键出战使用。
func get_undeployed_tiles_highest_first() -> Array[ArcherTile]:
	var result: Array[ArcherTile] = []

	for row in range(BOARD_SIZE):
		for column in range(BOARD_SIZE):
			var tile := board[row][column] as ArcherTile

			if tile != null and not tile.deployed:
				result.append(tile)

	# 棋盘最多只有16个角色，简单选择排序足够，也便于保持类型明确。
	for start_index in range(result.size()):
		var highest_index := start_index

		for candidate_index in range(start_index + 1, result.size()):
			if result[candidate_index].value > result[highest_index].value:
				highest_index = candidate_index

		if highest_index != start_index:
			var temporary_tile: ArcherTile = result[start_index]
			result[start_index] = result[highest_index]
			result[highest_index] = temporary_tile

	return result
