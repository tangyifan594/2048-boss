class_name BattleHUD
extends Control


# ==================== 对外信号 ====================

# 老家生命降到0时发出；以后由Main处理失败状态。
signal base_destroyed

# 玩家点击继续按钮、请求开启下一波怪物时发出。
signal next_wave_requested

# 玩家在失败面板点击重新开始时发出。
signal restart_requested

# 玩家主动跳过首次教程时发出。
signal tutorial_skipped


# ==================== 老家配置 ====================

@export var max_base_health: int = 10


# ==================== 节点与数据 ====================

@onready var health_bar: ProgressBar = $BaseHealth/HealthBar
@onready var health_label: Label = $BaseHealth/HealthBar/HealthLabel
@onready var pause_button: Button = $PauseButton
@onready var continue_wave_button: Button = $ContinueWaveButton
@onready var continue_icon: TextureRect = $ContinueWaveButton/ContinueIcon
@onready var speed_label: Label = $ContinueWaveButton/SpeedLabel
@onready var wave_status_label: Label = $WaveStatus/WaveStatusLabel
@onready var best_wave_label: Label = $WaveStatus/BestWaveLabel
@onready var notice_label: Label = $NoticeLabel
@onready var tutorial_panel: Panel = $TutorialPanel
@onready var tutorial_step_label: Label = $TutorialPanel/StepLabel
@onready var tutorial_instruction_label: Label = $TutorialPanel/InstructionLabel
@onready var tutorial_skip_button: Button = $TutorialPanel/SkipButton
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_wave_label: Label = $GameOverOverlay/GameOverPanel/Content/WaveLabel
@onready var restart_button: Button = $GameOverOverlay/GameOverPanel/Content/RestartButton

var current_base_health := 0
var displayed_wave_number := 1
var displayed_wave_total := 0
var displayed_best_wave := 0
var displayed_next_elite_wave := 6
var notice_tween: Tween = null


# ==================== 初始化 ====================

# 功能：初始化老家血量，并监听暂停按钮。
func _ready() -> void:
	current_base_health = maxi(max_base_health, 1)
	health_bar.max_value = current_base_health
	set_base_health(current_base_health)
	show_next_wave_ready(0)
	pause_button.pressed.connect(_on_pause_button_pressed)
	continue_wave_button.pressed.connect(_on_continue_wave_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	tutorial_skip_button.pressed.connect(_on_tutorial_skip_button_pressed)


# ==================== 老家血量 ====================

# 功能：直接设置老家当前生命并刷新显示。
func set_base_health(new_health: int) -> void:
	current_base_health = clampi(new_health, 0, maxi(max_base_health, 1))
	health_bar.value = current_base_health
	health_label.text = "%d / %d" % [current_base_health, max_base_health]


# 功能：老家受到伤害；以后由走到终点的Orc调用。
func damage_base(damage: int) -> void:
	if damage <= 0 or current_base_health <= 0:
		return

	set_base_health(current_base_health - damage)

	if current_base_health <= 0:
		base_destroyed.emit()


# 功能：恢复老家生命；满血或生命已归零时不使用道具。
func restore_base_health(heal_amount: int) -> bool:
	if heal_amount <= 0 or current_base_health <= 0:
		return false

	if current_base_health >= max_base_health:
		return false

	set_base_health(current_base_health + heal_amount)
	play_restore_feedback()
	return true


# 功能：供Main判断恢复道具是否会因为满血而无效。
func is_base_health_full() -> bool:
	return current_base_health >= max_base_health


# 功能：恢复成功时让生命图标和血条短暂变亮。
func play_restore_feedback() -> void:
	var heart_icon := $BaseHealth/HeartIcon as TextureRect
	heart_icon.modulate = Color(0.55, 1.0, 0.55, 1.0)
	health_bar.modulate = Color(0.65, 1.0, 0.65, 1.0)

	var restore_tween := create_tween()
	restore_tween.set_parallel(true)
	restore_tween.tween_property(heart_icon, "modulate", Color.WHITE, 0.3)
	restore_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.3)


# 功能：满血误点恢复道具时，让血量区域闪亮但不改变生命。
func play_full_health_feedback() -> void:
	var heart_icon := $BaseHealth/HeartIcon as TextureRect
	heart_icon.modulate = Color(1.0, 0.86, 0.32, 1.0)
	health_bar.modulate = Color(1.0, 0.86, 0.32, 1.0)

	var full_health_tween := create_tween()
	full_health_tween.set_parallel(true)
	full_health_tween.tween_property(heart_icon, "modulate", Color.WHITE, 0.35)
	full_health_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.35)


# ==================== 操作提醒 ====================

# 功能：在波次栏下方显示短暂英文提醒，重复触发时重新计时。
func show_notice(message: String, color: Color) -> void:
	if notice_tween != null and notice_tween.is_valid():
		notice_tween.kill()

	notice_label.text = message
	notice_label.add_theme_color_override("font_color", color)
	notice_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	notice_label.show()

	notice_tween = create_tween()
	notice_tween.tween_property(notice_label, "modulate:a", 1.0, 0.08)
	notice_tween.tween_interval(0.9)
	notice_tween.tween_property(notice_label, "modulate:a", 0.0, 0.22)
	notice_tween.finished.connect(notice_label.hide)


# ==================== 首次教程 ====================

# 功能：显示指定教程步骤；教程会由玩家的实际操作自动推进。
func show_tutorial_step(step: int) -> void:
	var safe_step := clampi(step, 1, 3)
	tutorial_step_label.text = "TIP %d / 3" % safe_step

	if safe_step == 1:
		tutorial_instruction_label.text = "USE ARROW KEYS TO MERGE HEROES"
	elif safe_step == 2:
		tutorial_instruction_label.text = "DRAG A HERO TO A SLOT OR PRESS AUTO"
	else:
		tutorial_instruction_label.text = "PRESS ▶ TO START THE NEXT WAVE"

	tutorial_panel.show()


# 功能：教程完成或跳过后隐藏提示面板。
func hide_tutorial() -> void:
	tutorial_panel.hide()


# 功能：把跳过操作通知Main保存，避免下次启动再次显示。
func _on_tutorial_skip_button_pressed() -> void:
	tutorial_skipped.emit()


# ==================== 暂停与继续 ====================

# 功能：切换整个游戏的暂停状态；暂停图标不承担开启下一波的职责。
func _on_pause_button_pressed() -> void:
	var should_pause := not get_tree().paused
	get_tree().paused = should_pause
	pause_button.set_pressed_no_signal(should_pause)
	pause_button.modulate = (
		Color(1.0, 0.85, 0.45, 1.0)
		if should_pause
		else Color.WHITE
	)
	pause_button.tooltip_text = "Resume Game" if should_pause else "Pause Game"


# ==================== 下一波 ====================

# 功能：请求波次系统放出下一波怪物。
func _on_continue_wave_button_pressed() -> void:
	if get_tree().paused:
		return

	print("Wave button: request received")
	next_wave_requested.emit()


# 功能：准备阶段启用下一波按钮，失败状态则禁用。
func set_next_wave_button_enabled(is_enabled: bool) -> void:
	continue_wave_button.disabled = not is_enabled
	speed_label.hide()
	continue_icon.position.x = 21.0
	continue_wave_button.modulate = (
		Color.WHITE
		if is_enabled
		else Color(0.55, 0.55, 0.55, 0.85)
	)
	continue_wave_button.tooltip_text = (
		"Start Next Wave" if is_enabled else "Unavailable"
	)


# 功能：波次开始后，按钮改为可切换2倍速。
func show_fast_forward_available() -> void:
	continue_wave_button.disabled = false
	continue_wave_button.modulate = Color.WHITE
	continue_wave_button.tooltip_text = "Enable 2x Speed"
	continue_icon.position.x = 8.0
	speed_label.show()
	speed_label.modulate = Color.WHITE


# 功能：刷新2倍速开关状态；开启后仍可再次点击来恢复正常速度。
func set_fast_forward_active(is_active: bool) -> void:
	continue_wave_button.disabled = false
	continue_wave_button.modulate = (
		Color(1.0, 0.82, 0.32, 1.0) if is_active else Color.WHITE
	)
	continue_wave_button.tooltip_text = (
		"Return to Normal Speed" if is_active else "Enable 2x Speed"
	)
	continue_icon.position.x = 8.0
	speed_label.show()
	speed_label.modulate = (
		Color(1.0, 0.90, 0.45, 1.0) if is_active else Color.WHITE
	)


# ==================== 波次状态显示 ====================

# 功能：显示本机保存的历史最高波次。
func set_best_wave(best_wave: int) -> void:
	displayed_best_wave = maxi(best_wave, 0)
	refresh_wave_progress_label()


# 功能：显示下一次怪物强度升级所在的波次。
func set_next_elite_wave(next_elite_wave: int) -> void:
	displayed_next_elite_wave = maxi(next_elite_wave, 1)
	refresh_wave_progress_label()


# 功能：把最高纪录和下一精英波紧凑地放在波次框第二行。
func refresh_wave_progress_label() -> void:
	best_wave_label.text = "BEST %d  ·  NEXT ELITE WAVE %d" % [
		displayed_best_wave,
		displayed_next_elite_wave,
	]

# 功能：波次开始时显示当前波次和完整怪物数量。
func show_wave_started(wave_number: int, total_enemies: int) -> void:
	displayed_wave_number = maxi(wave_number, 1)
	displayed_wave_total = maxi(total_enemies, 0)
	set_wave_enemy_count(displayed_wave_total, displayed_wave_total)


# 功能：刷新本波剩余怪物数量。
func set_wave_enemy_count(remaining_enemies: int, total_enemies: int) -> void:
	displayed_wave_total = maxi(total_enemies, 0)
	wave_status_label.text = "WAVE %d  ·  %d / %d LEFT" % [
		displayed_wave_number,
		maxi(remaining_enemies, 0),
		displayed_wave_total,
	]


# 功能：波次结束后显示下一波的准备状态。
func show_next_wave_ready(completed_wave_number: int) -> void:
	displayed_wave_number = maxi(completed_wave_number + 1, 1)
	displayed_wave_total = 0
	wave_status_label.text = "WAVE %d  ·  READY" % displayed_wave_number


# ==================== 失败与重新开始 ====================

# 功能：显示失败面板，并记录玩家坚持到的波次。
func show_game_over(reached_wave_number: int) -> void:
	set_next_wave_button_enabled(false)
	pause_button.disabled = true
	game_over_wave_label.text = "Reached Wave %d" % maxi(reached_wave_number, 1)
	game_over_overlay.show()
	restart_button.grab_focus()


# 功能：把重新开始请求交给Main统一处理。
func _on_restart_button_pressed() -> void:
	restart_requested.emit()


# 功能：离开主场景时恢复运行，防止重新进入后仍处于暂停状态。
func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false
