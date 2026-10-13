class_name BattleArcher
extends Node2D


# ==================== 场景资源 ====================

const ARROW_SCENE := preload("res://scene/Arrow.tscn")


# ==================== 射手配置 ====================

# 攻击动画播放到这一帧时生成箭矢。
@export var arrow_release_frame: int = 7

# 1级射手两次开始攻击之间的基础间隔。
@export var base_attack_cooldown: float = 1.2

# 每提高1级增加的攻击速度比例；当前为0，暂时不让等级影响射速。
# 例如改成0.08，代表每级增加8%攻击速度。
@export_range(0.0, 1.0, 0.01) var attack_speed_bonus_per_level: float = 0.0

# 无论等级多高，攻击间隔都不能低于这个值。
@export var minimum_attack_cooldown: float = 0.35


# ==================== 射手数据 ====================

# 来自2048棋子的数值，例如2、4、8。
var hero_value: int = 2

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle

var attack_target: Node2D = null
var projectile_parent: Node = null
var is_attacking := false
var arrow_released := false
var attack_cooldown_remaining := 0.0


# ==================== 初始化 ====================

# 功能：监听攻击动画的放箭帧和结束事件。
func _ready() -> void:
	animated_sprite.frame_changed.connect(_on_animation_frame_changed)
	animated_sprite.animation_finished.connect(_on_animation_finished)


# 功能：独立计算攻击冷却，不再使用动画长度充当射速。
func _process(delta: float) -> void:
	attack_cooldown_remaining = maxf(
		attack_cooldown_remaining - delta,
		0.0
	)


# 功能：根据棋盘角色数值设置战斗射手。
func setup_from_tile(tile_value: int) -> void:
	hero_value = maxi(tile_value, 2)


# ==================== 动画 ====================

# 功能：播放攻击动作，并在指定帧向目标生成一支箭。
func attack(target: Node2D, arrow_parent: Node) -> void:
	if not can_attack() or not is_instance_valid(target) or arrow_parent == null:
		return

	is_attacking = true
	arrow_released = false
	attack_cooldown_remaining = get_attack_cooldown()
	attack_target = target
	projectile_parent = arrow_parent
	animated_sprite.play("attack")


# 功能：动画已结束且冷却归零时，才允许开始下一次攻击。
func can_attack() -> bool:
	return not is_attacking and attack_cooldown_remaining <= 0.0


# 功能：到达放箭帧时创建Arrow场景。
func _on_animation_frame_changed() -> void:
	if animated_sprite.animation != &"attack" or arrow_released:
		return

	if animated_sprite.frame < arrow_release_frame:
		return

	arrow_released = true

	if not is_instance_valid(attack_target) or projectile_parent == null:
		return

	var arrow := ARROW_SCENE.instantiate() as Arrow
	projectile_parent.add_child(arrow)
	arrow.global_position = muzzle.global_position
	arrow.launch(attack_target, get_attack_damage())


# 功能：攻击动作结束后恢复待机状态。
func _on_animation_finished() -> void:
	if animated_sprite.animation != &"attack":
		return

	is_attacking = false
	attack_target = null
	projectile_parent = null
	animated_sprite.play("idle")


# 功能：把2048数值换算成当前射手伤害；等级越高，成长会逐渐放缓。
# 当前关系约为：数值2、4、8、16、32分别造成1、2、3、6、12点伤害。
func get_attack_damage() -> int:
	var hero_level: int = get_hero_level()
	var original_damage: float = float(hero_value) / 2.0
	var growth_reduction: float = pow(0.93, maxi(hero_level - 1, 0))
	return maxi(roundi(original_damage * growth_reduction), 1)


# ==================== 等级与射速 ====================

# 功能：把2048数值换算为等级；数值2为1级、4为2级、8为3级。
func get_hero_level() -> int:
	var level := 1
	var working_value := maxi(hero_value, 2)

	while working_value > 2:
		working_value = int(working_value / 2)
		level += 1

	return level


# 功能：根据等级计算实际攻击间隔，并应用最低冷却限制。
func get_attack_cooldown() -> float:
	var extra_levels := maxi(get_hero_level() - 1, 0)
	var speed_multiplier := (
		1.0
		+ maxf(attack_speed_bonus_per_level, 0.0) * float(extra_levels)
	)
	var calculated_cooldown := (
		maxf(base_attack_cooldown, 0.05) / speed_multiplier
	)
	return maxf(calculated_cooldown, minimum_attack_cooldown)


# 功能：返回每秒攻击次数，供以后角色详情界面显示。
func get_attacks_per_second() -> float:
	return 1.0 / get_attack_cooldown()
