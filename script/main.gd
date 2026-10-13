extends Node2D


const SAVE_PATH := "user://progress.cfg"


# ==================== 游戏配置 ====================

# 测试阶段进入游戏时拥有的金币，可在Main检查器中修改。
@export var starting_coins: int = 100

# 每次真正移动或合并棋盘需要消耗的金币。
@export var slide_cost: int = 10


# ==================== 节点与数据 ====================

@onready var board: Board2048 = $UI/ScreenUI/Board2048
@onready var world: Node2D = $World
@onready var screen_ui: Control = $UI/ScreenUI
@onready var item_toolbar: ItemToolbar = $UI/ScreenUI/ItemToolbar
@onready var coin_display: CoinDisplay = $UI/ScreenUI/CoinDisplay
@onready var battle_hud: BattleHUD = $UI/ScreenUI/BattleHUD
@onready var deployment_platform: DeploymentPlatform = $UI/ScreenUI/DeploymentPlatform
@onready var wave_controller: WaveController = $World/WaveController
@onready var slide_cost_label: Label = $UI/ScreenUI/SlideCost/Content/CostLabel
@onready var background_music: AudioStreamPlayer = $BackgroundMusic
@onready var wave_clear_sound: AudioStreamPlayer = $WaveClearSound
@onready var coin_pickup_sound: AudioStreamPlayer = $CoinPickupSound
@onready var game_over_sound: AudioStreamPlayer = $GameOverSound
@onready var base_hit_sound: AudioStreamPlayer = $BaseHitSound

# 玩家当前拥有的金币。
var coins := 0
var is_game_over := false
var damage_shake_tween: Tween = null
var world_rest_position := Vector2.ZERO
var ui_rest_position := Vector2.ZERO
var best_wave := 0
var tutorial_complete := false
var tutorial_slide_done := false
var tutorial_deploy_done := false


# ==================== 初始化 ====================

# 功能：设置初始金币，并连接棋盘和道具栏之间的游戏规则。
func _ready() -> void:
	Engine.time_scale = 1.0
	configure_background_music_loop()
	load_progress()
	world_rest_position = world.position
	ui_rest_position = screen_ui.position
	coins = maxi(starting_coins, 0)
	coin_display.set_amount(coins)
	slide_cost_label.text = str(maxi(slide_cost, 0))
	battle_hud.set_best_wave(best_wave)
	battle_hud.set_next_elite_wave(wave_controller.get_next_elite_wave(0))

	board.slide_requested.connect(_on_slide_requested)
	item_toolbar.swap_requested.connect(_on_swap_requested)
	item_toolbar.restore_requested.connect(_on_restore_requested)
	board.swap_mode_changed.connect(item_toolbar.set_swap_mode_active)
	board.swap_completed.connect(_on_swap_completed)
	battle_hud.next_wave_requested.connect(_on_next_wave_requested)
	battle_hud.base_destroyed.connect(_on_base_destroyed)
	battle_hud.restart_requested.connect(_on_restart_requested)
	battle_hud.tutorial_skipped.connect(_on_tutorial_skipped)
	deployment_platform.auto_deploy_requested.connect(_on_auto_deploy_requested)
	deployment_platform.slot_unlock_requested.connect(_on_slot_unlock_requested)
	deployment_platform.archer_deployed.connect(_on_archer_deployed)
	wave_controller.coins_earned.connect(add_coins)
	wave_controller.base_damaged.connect(_on_base_damaged)
	wave_controller.wave_started.connect(_on_wave_started)
	wave_controller.enemy_count_changed.connect(battle_hud.set_wave_enemy_count)
	wave_controller.wave_finished.connect(_on_wave_finished)

	if not tutorial_complete:
		battle_hud.show_tutorial_step(1)


# ==================== 金币 ====================

# 功能：尝试扣除金币；余额不足时返回false。
func spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false

	coins -= amount
	coin_display.set_amount(coins)
	return true


# 功能：增加金币；以后由击杀怪物和波次奖励调用。
func add_coins(amount: int) -> void:
	if amount <= 0:
		return

	coins += amount
	coin_display.set_amount(coins)
	coin_pickup_sound.play()


# ==================== 2048滑动付费 ====================

# 功能：钱够时尝试滑动；只有棋盘真的移动或合并才扣除金币。
func _on_slide_requested(direction: Vector2i) -> void:
	if coins < slide_cost:
		coin_display.play_not_enough_feedback()
		return

	if board.perform_turn(direction):
		spend_coins(slide_cost)
		mark_tutorial_slide_done()


# ==================== 交换道具购买 ====================

# 功能：检查交换价格；钱够才允许棋盘进入交换模式。
func _on_swap_requested() -> void:
	if board.is_animating:
		item_toolbar.set_swap_mode_active(false)
		return

	if board.is_swap_mode:
		board.cancel_swap_mode()
		return

	if board.has_deployed_tiles():
		item_toolbar.set_swap_mode_active(false)
		return

	if coins < item_toolbar.exchange_cost:
		item_toolbar.set_swap_mode_active(false)
		coin_display.play_not_enough_feedback()
		return

	board.begin_swap_mode()


# 功能：只有两个角色实际完成交换后，才扣除20金币。
func _on_swap_completed() -> void:
	spend_coins(item_toolbar.exchange_cost)


# ==================== 恢复道具购买 ====================

# 功能：支付30金币并恢复3点老家生命；满血时不消费。
func _on_restore_requested() -> void:
	if is_game_over:
		return

	if battle_hud.is_base_health_full():
		battle_hud.play_full_health_feedback()
		battle_hud.show_notice(
			"BASE HEALTH IS FULL",
			Color(1.0, 0.86, 0.32, 1.0)
		)
		return

	if coins < item_toolbar.restore_cost:
		coin_display.play_not_enough_feedback()
		return

	if not battle_hud.restore_base_health(item_toolbar.restore_amount):
		return

	spend_coins(item_toolbar.restore_cost)


# ==================== 自动战斗波次 ====================

# 功能：波次开始时刷新界面，并在到达新纪录时保存BEST WAVE。
func _on_wave_started(wave_number: int, total_enemies: int) -> void:
	battle_hud.show_wave_started(wave_number, total_enemies)
	battle_hud.set_next_elite_wave(
		wave_controller.get_next_elite_wave(wave_number)
	)
	complete_tutorial()

	if wave_number <= best_wave:
		return

	best_wave = wave_number
	battle_hud.set_best_wave(best_wave)
	save_progress()


# ==================== 首次教程进度 ====================

# 功能：完成第一次有效滑动后，推进到部署提示。
func mark_tutorial_slide_done() -> void:
	if tutorial_complete:
		return

	tutorial_slide_done = true
	refresh_tutorial_step()


# 功能：手动拖动或AUTO成功部署后，推进到开波提示。
func _on_archer_deployed(_tile: ArcherTile, _slot_index: int) -> void:
	if tutorial_complete:
		return

	tutorial_deploy_done = true
	refresh_tutorial_step()


# 功能：始终显示最早一个尚未完成的教程操作。
func refresh_tutorial_step() -> void:
	if tutorial_complete:
		return

	if not tutorial_slide_done:
		battle_hud.show_tutorial_step(1)
	elif not tutorial_deploy_done:
		battle_hud.show_tutorial_step(2)
	else:
		battle_hud.show_tutorial_step(3)


# 功能：首次正式开波后完成教程并保存。
func complete_tutorial() -> void:
	if tutorial_complete:
		return

	tutorial_complete = true
	battle_hud.hide_tutorial()
	save_progress()


# 功能：玩家点击SKIP时直接完成教程。
func _on_tutorial_skipped() -> void:
	complete_tutorial()

# 功能：用棋盘中等级最高的角色依次填满出战台空位。
func _on_auto_deploy_requested() -> void:
	if is_game_over or board.is_animating or board.is_swap_mode or board.is_battle_locked:
		return

	deployment_platform.auto_deploy_tiles(
		board.get_undeployed_tiles_highest_first()
	)


# 功能：购买指定出战位；金币不足时播放现有错误反馈。
func _on_slot_unlock_requested(slot_index: int, unlock_cost: int) -> void:
	if is_game_over or board.is_battle_locked:
		return

	if deployment_platform.is_slot_unlocked(slot_index):
		return

	if coins < unlock_cost:
		coin_display.play_not_enough_feedback()
		return

	if deployment_platform.unlock_slot(slot_index):
		spend_coins(unlock_cost)


# 功能：点击下一波后锁定棋盘，并让波次系统开始生成Orc。
func _on_next_wave_requested() -> void:
	if is_game_over:
		return

	if wave_controller.wave_active:
		var fast_forward_enabled := wave_controller.toggle_fast_forward()
		battle_hud.set_fast_forward_active(fast_forward_enabled)
		return

	if deployment_platform.get_deployed_archers().is_empty():
		deployment_platform.play_empty_deployment_feedback()
		battle_hud.show_notice(
			"DEPLOY A HERO FIRST",
			Color(1.0, 0.44, 0.32, 1.0)
		)
		return

	if not wave_controller.start_wave(deployment_platform):
		return

	board.set_battle_locked(true)
	deployment_platform.set_deployment_locked(true)
	battle_hud.show_fast_forward_available()


# 功能：本波结束后让角色归队，恢复棋盘和下一波按钮。
func _on_wave_finished() -> void:
	if is_game_over:
		return

	wave_clear_sound.play()
	deployment_platform.clear_deployments()
	deployment_platform.set_deployment_locked(false)
	board.set_battle_locked(false)
	battle_hud.set_next_wave_button_enabled(true)
	battle_hud.show_next_wave_ready(wave_controller.current_wave_number)
	battle_hud.set_next_elite_wave(
		wave_controller.get_next_elite_wave(
			wave_controller.current_wave_number
		)
	)


# ==================== 老家受伤反馈 ====================

# 功能：先播放画面抖动，再让老家扣除生命值。
func _on_base_damaged(damage: int) -> void:
	play_damage_shake()
	battle_hud.damage_base(damage)

	# 致命伤害只播放失败声，避免Gunshot和Game Over重叠。
	if not is_game_over:
		base_hit_sound.play()


# 功能：让战场与UI同步进行一次短促抖动。
func play_damage_shake() -> void:
	reset_damage_shake()

	damage_shake_tween = create_tween()
	damage_shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	damage_shake_tween.tween_method(
		apply_damage_shake_offset,
		Vector2.ZERO,
		Vector2(-7.0, 3.0),
		0.04
	)
	damage_shake_tween.tween_method(
		apply_damage_shake_offset,
		Vector2(-7.0, 3.0),
		Vector2(6.0, -3.0),
		0.05
	)
	damage_shake_tween.tween_method(
		apply_damage_shake_offset,
		Vector2(6.0, -3.0),
		Vector2(-4.0, 2.0),
		0.05
	)
	damage_shake_tween.tween_method(
		apply_damage_shake_offset,
		Vector2(-4.0, 2.0),
		Vector2(3.0, -1.0),
		0.05
	)
	damage_shake_tween.tween_method(
		apply_damage_shake_offset,
		Vector2(3.0, -1.0),
		Vector2.ZERO,
		0.06
	)
	damage_shake_tween.finished.connect(reset_damage_shake)


# 功能：把同一个抖动偏移同时应用到战场和UI。
func apply_damage_shake_offset(offset: Vector2) -> void:
	world.position = world_rest_position + offset
	screen_ui.position = ui_rest_position + offset


# 功能：终止旧抖动并恢复准确位置，避免连续受伤产生位置漂移。
func reset_damage_shake() -> void:
	if damage_shake_tween != null and damage_shake_tween.is_valid():
		damage_shake_tween.kill()

	damage_shake_tween = null
	world.position = world_rest_position
	screen_ui.position = ui_rest_position


# ==================== 失败与重新开始 ====================

# 功能：老家生命归零后停止所有战斗，并显示失败界面。
func _on_base_destroyed() -> void:
	if is_game_over:
		return

	is_game_over = true
	background_music.stop()
	base_hit_sound.stop()
	game_over_sound.play()
	wave_controller.stop_current_wave()
	deployment_platform.set_deployment_locked(true)
	board.set_battle_locked(true)
	battle_hud.show_game_over(wave_controller.current_wave_number)
	get_tree().paused = true


# 功能：解除暂停并重新加载主场景，恢复一局全新的游戏。
func _on_restart_requested() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ==================== 音乐 ====================

# 功能：确保背景音乐循环播放，不依赖素材导入设置。
func configure_background_music_loop() -> void:
	var music_stream := background_music.stream as AudioStreamMP3

	if music_stream != null:
		music_stream.loop = true


# 功能：退出或重新加载场景前停止音频，避免留下仍在播放的资源。
func _exit_tree() -> void:
	background_music.stop()
	wave_clear_sound.stop()
	coin_pickup_sound.stop()
	game_over_sound.stop()
	base_hit_sound.stop()
	background_music.stream = null
	wave_clear_sound.stream = null
	coin_pickup_sound.stream = null
	game_over_sound.stream = null
	base_hit_sound.stream = null


# ==================== 本地进度 ====================

# 功能：读取历史最高波次；首次运行或存档损坏时使用0。
func load_progress() -> void:
	var progress := ConfigFile.new()
	var load_result := progress.load(SAVE_PATH)

	if load_result != OK:
		best_wave = 0
		return

	best_wave = maxi(int(progress.get_value("progress", "best_wave", 0)), 0)
	tutorial_complete = bool(
		progress.get_value("progress", "tutorial_complete", false)
	)


# 功能：保存最高波次；Web版本会写入Godot的user数据目录。
func save_progress() -> void:
	var progress := ConfigFile.new()
	progress.set_value("progress", "best_wave", best_wave)
	progress.set_value("progress", "tutorial_complete", tutorial_complete)
	progress.save(SAVE_PATH)
