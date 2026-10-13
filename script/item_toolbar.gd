class_name ItemToolbar
extends Control


# ==================== 道具配置 ====================

# 交换任意两个角色需要的金币数量。
@export var exchange_cost: int = 20

# 恢复3点老家生命需要的金币数量。
@export var restore_cost: int = 30

# 每次恢复道具提供的生命值。
@export var restore_amount: int = 3


# ==================== 对外信号 ====================

# 点击交换道具后发出；下一步由主场景把它连接到棋盘。
signal swap_requested

# 点击恢复道具后发出，由Main检查金币和老家生命值。
signal restore_requested


# ==================== 节点引用 ====================

# 第一格中的交换按钮。
@onready var exchange_button: Button = $ExchangeButton

# 交换按钮下方显示的金币价格。
@onready var exchange_cost_label: Label = $ExchangeButton/Price/CostLabel

# 第二格中的恢复按钮及其价格。
@onready var restore_button: Button = $RestoreButton
@onready var restore_cost_label: Label = $RestoreButton/Price/CostLabel


# ==================== 初始化 ====================

# 功能：监听交换按钮的点击。
func _ready() -> void:
	exchange_cost_label.text = str(exchange_cost)
	restore_cost_label.text = str(restore_cost)
	exchange_button.pressed.connect(_on_exchange_button_pressed)
	restore_button.pressed.connect(_on_restore_button_pressed)


# ==================== 交换道具 ====================

# 功能：发出交换请求；目前同时打印文字，方便单独测试道具栏。
func _on_exchange_button_pressed() -> void:
	print("Swap item button: clicked")
	swap_requested.emit()


# ==================== 恢复道具 ====================

# 功能：请求恢复老家生命，是否扣费由Main统一决定。
func _on_restore_button_pressed() -> void:
	restore_requested.emit()


# 功能：根据棋盘状态更新交换按钮的选中反馈。
func set_swap_mode_active(is_active: bool) -> void:
	exchange_button.set_pressed_no_signal(is_active)

	if is_active:
		exchange_button.modulate = Color(1.0, 0.85, 0.45, 1.0)
	else:
		exchange_button.modulate = Color.WHITE
