class_name ArcherTile
extends Control


# ==================== 对外信号 ====================

# 玩家用鼠标点击这个角色时发出。
signal tile_clicked(tile: ArcherTile)


# ==================== 角色状态 ====================

@export var value: int = 2
@export var selected: bool = false

# 角色是否已经被安排到出战台。
var deployed := false

@onready var value_label: Label = $ValueLabel
@onready var selection_border: Panel = $SelectionBorder
@onready var archer_sprite: AnimatedSprite2D = $ArcherSprite2


# ==================== 初始化 ====================

# 功能：刷新角色画面，并把缩放中心放在角色中央。
func _ready() -> void:
	pivot_offset = size * 0.5
	refresh_display()
	refresh_selection()


# ==================== 鼠标点击 ====================

# 功能：把角色上的鼠标左键点击通知给棋盘。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			tile_clicked.emit(self)
			accept_event()


# 功能：开始拖动时提供角色数据和跟随鼠标的预览。
func _get_drag_data(_at_position: Vector2) -> Variant:
	var board_node := get_parent().get_parent() as Board2048

	if board_node == null or not board_node.can_start_tile_drag(self):
		return null

	var preview := create_drag_preview()
	set_drag_preview(preview)

	return {
		"type": "archer_tile",
		"tile": self,
		"value": value,
	}


# 功能：拖着出战射手放到已有角色上时，把事件转交给整个棋盘。
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var board_node := get_parent().get_parent() as Board2048
	return board_node != null and board_node.can_accept_archer_return(data)


# 功能：在角色区域放开鼠标时，执行撤回出战射手。
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var board_node := get_parent().get_parent() as Board2048

	if board_node != null:
		board_node.accept_archer_return(data)


# 功能：创建拖动时显示的角色副本，不移动真正的棋盘节点。
func create_drag_preview() -> Control:
	var preview := Control.new()
	preview.custom_minimum_size = size
	preview.size = size
	preview.scale = get_global_transform().get_scale()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)

	var sprite_copy := archer_sprite.duplicate() as AnimatedSprite2D
	var label_copy := value_label.duplicate() as Label
	preview.add_child(sprite_copy)
	preview.add_child(label_copy)

	return preview


# ==================== 数值显示 ====================

# 功能：修改角色数值，并刷新数字显示。
func set_value(new_value: int) -> void:
	value = new_value
	refresh_display()


# 功能：把当前角色数值显示到标签上。
func refresh_display() -> void:
	if not is_node_ready():
		return

	value_label.text = str(value)


# ==================== 选中状态 ====================

# 功能：修改角色的选中状态。
func set_selected(is_selected: bool) -> void:
	selected = is_selected
	refresh_selection()


# 功能：根据选中状态显示或隐藏金色边框。
func refresh_selection() -> void:
	if not is_node_ready():
		return

	selection_border.visible = selected


# 功能：切换出战状态；出战中的棋盘角色变暗并禁止再次拖动。
func set_deployed(is_deployed: bool) -> void:
	deployed = is_deployed
	modulate = Color(0.45, 0.45, 0.45, 0.75) if deployed else Color.WHITE


# ==================== 角色动画 ====================

# 功能：新角色生成时，从较小尺寸弹出到正常尺寸。
func play_spawn_animation() -> void:
	scale = Vector2(0.65, 0.65)

	var tween := create_tween()
	tween.tween_property(
		self,
		"scale",
		Vector2.ONE,
		0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 功能：角色合并升级时，先放大再恢复正常尺寸。
func play_merge_animation() -> void:
	scale = Vector2.ONE

	var tween := create_tween()
	tween.tween_property(
		self,
		"scale",
		Vector2(1.16, 1.16),
		0.06
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self,
		"scale",
		Vector2.ONE,
		0.08
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
