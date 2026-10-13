class_name Orc
extends CharacterBody2D


# ==================== 对外信号 ====================

# 兽人死亡时把金币奖励通知给波次或主场景。
signal died(coin_reward: int)

# 兽人走到道路终点时，把老家伤害通知给波次系统。
signal reached_base(damage: int)


# ==================== 小怪配置 ====================

@export var max_health: int = 5
@export var move_speed: float = 45.0
@export var coin_reward: int = 7
@export var base_damage: int = 1
@export var destination_x: float = 570.0
# 普通兽人可用颜色表现第一次强化；装甲兽人关闭染色，保留盔甲原色。
@export var use_tier_tint: bool = true
# 不同敌人外形在同一波次等级上的额外差异。
@export var archetype_health_multiplier: float = 1.0
@export var archetype_reward_multiplier: float = 1.0
@export var archetype_speed_multiplier: float = 1.0
@export var archetype_base_damage_bonus: int = 0


# ==================== 小怪数据 ====================

var current_health := 0
var can_move := true
var is_dying := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var health_bar: ProgressBar = $HealthBar

var hit_flash_tween: Tween = null
var enemy_tier := 0
var normal_sprite_color := Color.WHITE


# ==================== 初始化 ====================

# 功能：进入场景时恢复满生命。
func _ready() -> void:
	current_health = maxi(max_health, 1)
	health_bar.max_value = current_health
	health_bar.value = current_health
	animated_sprite.animation_finished.connect(_on_animation_finished)


# 功能：根据当前波次阶段强化生命、奖励和速度，并用颜色区分强化怪。
func apply_wave_scaling(
	tier: int,
	health_multiplier_per_tier: float,
	reward_multiplier_per_tier: float,
	speed_bonus_per_tier: float
) -> void:
	enemy_tier = maxi(tier, 0)
	var health_scale: float = pow(maxf(health_multiplier_per_tier, 1.0), enemy_tier)
	var reward_scale: float = pow(maxf(reward_multiplier_per_tier, 1.0), enemy_tier)
	var speed_scale: float = 1.0 + maxf(speed_bonus_per_tier, 0.0) * enemy_tier

	max_health = maxi(
		roundi(max_health * health_scale * maxf(archetype_health_multiplier, 0.1)),
		1
	)
	coin_reward = maxi(
		roundi(coin_reward * reward_scale * maxf(archetype_reward_multiplier, 0.1)),
		1
	)
	move_speed *= speed_scale * maxf(archetype_speed_multiplier, 0.1)
	base_damage = (
		1
		+ floori(float(enemy_tier) / 2.0)
		+ maxi(archetype_base_damage_bonus, 0)
	)

	if use_tier_tint and enemy_tier > 0:
		var tier_tint_strength: float = minf(0.12 * enemy_tier, 0.42)
		normal_sprite_color = Color.WHITE.lerp(
			Color(1.0, 0.55, 0.28, 1.0),
			tier_tint_strength
		)

	animated_sprite.modulate = normal_sprite_color
	current_health = max_health
	health_bar.max_value = max_health
	health_bar.value = current_health


# ==================== 移动 ====================

# 功能：让兽人持续从画面左侧向右侧前进。
func _physics_process(_delta: float) -> void:
	if not can_move:
		velocity = Vector2.ZERO
		return

	if global_position.x >= destination_x:
		reach_base()
		return

	velocity = Vector2.RIGHT * move_speed
	move_and_slide()


# 功能：到达道路终点，伤害老家并从本波移除。
func reach_base() -> void:
	if is_dying or not can_move:
		return

	can_move = false
	velocity = Vector2.ZERO
	reached_base.emit(maxi(base_damage, 1))
	queue_free()


# ==================== 受伤与死亡 ====================

# 功能：受到攻击并扣除生命值。
func take_damage(damage: int) -> void:
	if damage <= 0 or current_health <= 0 or is_dying:
		return

	current_health = maxi(current_health - damage, 0)
	health_bar.value = current_health
	play_hit_feedback(damage)

	if current_health <= 0:
		die()


# ==================== 受击反馈 ====================

# 功能：让兽人短暂闪红，并在头顶显示本次伤害数字。
func play_hit_feedback(damage: int) -> void:
	if hit_flash_tween != null and hit_flash_tween.is_valid():
		hit_flash_tween.kill()

	animated_sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	hit_flash_tween = create_tween()
	hit_flash_tween.tween_property(
		animated_sprite,
		"modulate",
		normal_sprite_color,
		0.12
	)

	create_damage_number(damage)


# 功能：创建一个向上飘动并逐渐消失的伤害数字。
func create_damage_number(damage: int) -> void:
	var damage_label := Label.new()
	damage_label.z_index = 20
	damage_label.position = Vector2(-24.0, -78.0)
	damage_label.size = Vector2(48.0, 24.0)
	damage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_label.text = "-%d" % damage
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 1.0))
	damage_label.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.02, 1.0))
	damage_label.add_theme_constant_override("outline_size", 3)
	damage_label.add_theme_font_size_override("font_size", 17)
	add_child(damage_label)

	var number_tween := create_tween()
	number_tween.set_parallel(true)
	number_tween.tween_property(
		damage_label,
		"position:y",
		damage_label.position.y - 22.0,
		0.45
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	number_tween.tween_property(
		damage_label,
		"modulate:a",
		0.0,
		0.45
	)
	number_tween.finished.connect(damage_label.queue_free)


# 功能：通知外部发放金币，然后移除小怪。
func die() -> void:
	if is_dying:
		return

	is_dying = true
	can_move = false
	velocity = Vector2.ZERO
	health_bar.hide()
	collision_shape.set_deferred("disabled", true)
	animated_sprite.play("death")


# 功能：死亡动画完整播放后再发金币并移除节点。
func _on_animation_finished() -> void:
	if animated_sprite.animation != &"death":
		return

	died.emit(coin_reward)
	queue_free()
