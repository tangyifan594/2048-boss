class_name Arrow
extends Area2D


# ==================== 箭矢配置 ====================

@export var speed: float = 420.0
@export var damage: int = 1


# ==================== 箭矢数据 ====================

var target: Node2D = null


# ==================== 发射 ====================

# 功能：设置箭矢目标与伤害。
func launch(new_target: Node2D, new_damage: int) -> void:
	target = new_target
	damage = maxi(new_damage, 1)


# ==================== 飞行与命中 ====================

# 功能：持续飞向目标；素材默认朝右，所以直接使用方向角度。
func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return

	var target_position := target.global_position
	var direction := global_position.direction_to(target_position)
	var travel_distance := speed * delta

	rotation = direction.angle()

	if global_position.distance_to(target_position) <= travel_distance + 8.0:
		hit_target()
		return

	global_position += direction * travel_distance


# 功能：命中后对目标造成伤害，并删除箭矢。
func hit_target() -> void:
	if is_instance_valid(target) and target.has_method("take_damage"):
		target.call("take_damage", damage)

	queue_free()
