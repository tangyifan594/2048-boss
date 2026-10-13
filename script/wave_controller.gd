class_name WaveController
extends Node


# ==================== 对外信号 ====================

# 小怪死亡后，把获得的金币交给Main处理。
signal coins_earned(amount: int)

# 小怪走到道路终点后，把老家伤害交给Main处理。
signal base_damaged(amount: int)

# 本波全部小怪都已死亡或到达终点时发出。
signal wave_finished

# 新波次开始时，通知UI当前波次和小怪总数。
signal wave_started(wave_number: int, total_enemies: int)

# 小怪离场时，通知UI更新本波剩余数量。
signal enemy_count_changed(remaining_enemies: int, total_enemies: int)


# ==================== 波次配置 ====================

const ORC_SCENE := preload("res://scene/Orc.tscn")
const ARMORED_ORC_SCENE := preload("res://scene/ArmoredOrc.tscn")
const ARMORED_ORC_TIER := 2

# 每个强度阶段的怪物数量。阶段末达到10只，下一阶段换成5只更强的怪物。
@export var enemies_per_tier: Array[int] = [5, 6, 7, 8, 10]
@export var health_multiplier_per_tier: float = 2.0
@export var reward_multiplier_per_tier: float = 1.5
@export var speed_bonus_per_tier: float = 0.04
# 45移动速度下，1.8秒约形成81像素间距，避免小怪血条互相覆盖。
@export var spawn_interval: float = 1.8
# 这里只是寻找目标的检查频率，真正射速由BattleArcher的冷却控制。
@export var attack_interval: float = 0.1
@export var archer_attack_range: float = 480.0
@export var enemy_spawn_position := Vector2(-45.0, 360.0)
@export var base_position_x: float = 570.0


# ==================== 节点与波次数据 ====================

@onready var monster_layer: Node2D = $"../MonsterLayer"
@onready var projectile_layer: Node2D = $"../ProjectileLayer"
@onready var spawn_timer: Timer = $SpawnTimer
@onready var attack_timer: Timer = $AttackTimer

var deployment_platform: DeploymentPlatform = null
var wave_active := false
var fast_forward_active := false
var current_wave_number := 0
var enemies_in_current_wave := 0
var enemies_waiting_to_spawn := 0
var enemies_alive := 0
var current_enemy_tier := 0
var enemy_lineup: Array[PackedScene] = []


# ==================== 初始化 ====================

# 功能：设置计时器并监听生成和自动攻击节拍。
func _ready() -> void:
	spawn_timer.wait_time = maxf(spawn_interval, 0.05)
	attack_timer.wait_time = maxf(attack_interval, 0.05)
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	attack_timer.timeout.connect(_on_attack_timer_timeout)


# ==================== 开启波次 ====================

# 功能：开启一波小怪；波次进行中不能重复开启。
func start_wave(platform: DeploymentPlatform) -> bool:
	if wave_active or platform == null:
		return false

	deployment_platform = platform
	wave_active = true
	set_fast_forward(false)
	current_wave_number += 1
	current_enemy_tier = get_enemy_tier_for_wave(current_wave_number)
	enemies_in_current_wave = get_enemy_count_for_wave(current_wave_number)
	enemies_waiting_to_spawn = enemies_in_current_wave
	enemies_alive = 0
	enemy_lineup = build_enemy_lineup(
		current_wave_number,
		enemies_in_current_wave
	)
	wave_started.emit(current_wave_number, enemies_in_current_wave)

	spawn_next_enemy()
	attack_timer.start()
	return true


# ==================== 生成小怪 ====================

# 功能：按时间间隔生成下一只敌人。
func _on_spawn_timer_timeout() -> void:
	spawn_next_enemy()


# 功能：根据强化阶段选择普通或装甲兽人，并连接离场事件。
func spawn_next_enemy() -> void:
	if not wave_active or enemies_waiting_to_spawn <= 0:
		spawn_timer.stop()
		return

	var spawn_index: int = enemies_in_current_wave - enemies_waiting_to_spawn
	var enemy_scene: PackedScene = ORC_SCENE
	if spawn_index >= 0 and spawn_index < enemy_lineup.size():
		enemy_scene = enemy_lineup[spawn_index]
	var orc := enemy_scene.instantiate() as Orc
	monster_layer.add_child(orc)
	orc.apply_wave_scaling(
		current_enemy_tier,
		health_multiplier_per_tier,
		reward_multiplier_per_tier,
		speed_bonus_per_tier
	)
	orc.global_position = enemy_spawn_position
	orc.destination_x = base_position_x
	orc.died.connect(_on_enemy_died)
	orc.reached_base.connect(_on_enemy_reached_base)

	enemies_waiting_to_spawn -= 1
	enemies_alive += 1

	if enemies_waiting_to_spawn > 0:
		spawn_timer.start()
	else:
		spawn_timer.stop()


# 功能：建立混合编队；装甲兽人出现后仍保留普通兽人。
# 第11波先把最后一只换成装甲兽人，之后每波增加一只并均匀穿插。
func build_enemy_lineup(wave_number: int, total_enemies: int) -> Array[PackedScene]:
	var lineup: Array[PackedScene] = []
	var safe_total: int = maxi(total_enemies, 1)

	for _enemy_index in range(safe_total):
		lineup.append(ORC_SCENE)

	var armored_count: int = get_armored_orc_count(wave_number, safe_total)
	if armored_count <= 0:
		return lineup

	for armored_index in range(armored_count):
		var lineup_index: int = (
			ceili(float(armored_index + 1) * float(safe_total) / float(armored_count))
			- 1
		)
		lineup[lineup_index] = ARMORED_ORC_SCENE

	return lineup


# 功能：装甲兽人从第二次强化开始加入，每过一波增加一只。
# 最多占本波约六成，确保普通兽人始终会一起出现。
func get_armored_orc_count(wave_number: int, total_enemies: int) -> int:
	var first_armored_wave: int = (
		ARMORED_ORC_TIER * maxi(enemies_per_tier.size(), 1) + 1
	)
	if wave_number < first_armored_wave:
		return 0

	var desired_count: int = wave_number - first_armored_wave + 1
	var mixed_lineup_limit: int = maxi(
		floori(float(total_enemies) * 0.6),
		1
	)
	return mini(desired_count, mixed_lineup_limit)


# ==================== 自动攻击 ====================

# 功能：每个攻击节拍，让全部已出战射手寻找最靠近老家的目标。
func _on_attack_timer_timeout() -> void:
	if not wave_active or deployment_platform == null:
		return

	for archer in deployment_platform.get_deployed_archers():
		if not is_instance_valid(archer):
			continue

		var target := find_target_for_archer(archer)

		if target != null:
			archer.attack(target, projectile_layer)


# 功能：在射程内选择横坐标最大的Orc，也就是最接近道路终点的敌人。
func find_target_for_archer(archer: BattleArcher) -> Orc:
	var best_target: Orc = null
	var best_progress := -INF

	for child in monster_layer.get_children():
		var orc := child as Orc

		if orc == null or orc.is_dying:
			continue

		var distance: float = archer.global_position.distance_to(orc.global_position)

		if distance > archer_attack_range:
			continue

		if orc.global_position.x > best_progress:
			best_progress = orc.global_position.x
			best_target = orc

	return best_target


# ==================== 小怪离场与结束波次 ====================

# 功能：小怪死亡时发放金币，并记录本波剩余数量。
func _on_enemy_died(coin_reward: int) -> void:
	coins_earned.emit(coin_reward)
	finish_one_enemy()


# 功能：小怪到达终点时伤害老家，并记录本波剩余数量。
func _on_enemy_reached_base(damage: int) -> void:
	base_damaged.emit(damage)
	finish_one_enemy()


# 功能：最后一只小怪离场后结束本波。
func finish_one_enemy() -> void:
	if not wave_active:
		return

	enemies_alive = maxi(enemies_alive - 1, 0)
	enemy_count_changed.emit(
		enemies_waiting_to_spawn + enemies_alive,
		enemies_in_current_wave
	)

	if enemies_waiting_to_spawn > 0 or enemies_alive > 0:
		return

	wave_active = false
	set_fast_forward(false)
	spawn_timer.stop()
	attack_timer.stop()
	deployment_platform = null
	enemy_lineup.clear()
	wave_finished.emit()


# ==================== 强制停止 ====================

# 功能：失败或离开游戏时停止当前波次，并清除怪物和箭矢。
func stop_current_wave() -> void:
	wave_active = false
	set_fast_forward(false)
	spawn_timer.stop()
	attack_timer.stop()
	enemies_waiting_to_spawn = 0
	enemies_alive = 0
	enemy_lineup.clear()
	deployment_platform = null

	for child in monster_layer.get_children():
		child.queue_free()

	for child in projectile_layer.get_children():
		child.queue_free()


# ==================== 战斗加速 ====================

# 功能：波次进行中在正常速度和2倍速之间切换，并返回切换后的状态。
func toggle_fast_forward() -> bool:
	if not wave_active:
		return false

	set_fast_forward(not fast_forward_active)
	return fast_forward_active


# 功能：统一设置游戏速度，确保波次结束和失败时恢复正常。
func set_fast_forward(is_enabled: bool) -> void:
	fast_forward_active = is_enabled
	Engine.time_scale = 2.0 if fast_forward_active else 1.0


# ==================== 波次成长 ====================

# 功能：每完成一个数量阶段，提高一次怪物强度。
func get_enemy_tier_for_wave(wave_number: int) -> int:
	var tier_length: int = maxi(enemies_per_tier.size(), 1)
	return floori(float(maxi(wave_number, 1) - 1) / float(tier_length))


# 功能：同一强度阶段内逐渐增加数量，换强度时重新从较少数量开始。
func get_enemy_count_for_wave(wave_number: int) -> int:
	if enemies_per_tier.is_empty():
		return 5

	var wave_index: int = maxi(wave_number, 1) - 1
	var count_index: int = wave_index % enemies_per_tier.size()
	return maxi(enemies_per_tier[count_index], 1)


# 功能：返回指定波次之后，下一个怪物强度升级的里程碑波次。
func get_next_elite_wave(after_wave_number: int) -> int:
	var tier_length: int = maxi(enemies_per_tier.size(), 1)
	var completed_tiers: int = floori(
		float(maxi(after_wave_number - 1, 0)) / float(tier_length)
	)
	return (completed_tiers + 1) * tier_length + 1


# 功能：离开当前场景时恢复全局速度，避免影响重新进入的游戏。
func _exit_tree() -> void:
	Engine.time_scale = 1.0
