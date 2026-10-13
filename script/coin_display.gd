class_name CoinDisplay
extends Control


# ==================== 节点引用 ====================

# 显示玩家当前金币数量的文字。
@onready var amount_label: Label = $Background/Content/AmountLabel

# 金币不足时播放的错误提示音。
@onready var error_sound: AudioStreamPlayer = $ErrorSound


# ==================== 金币显示 ====================

# 功能：刷新界面上的金币数量。
func set_amount(amount: int) -> void:
	amount_label.text = str(maxi(amount, 0))


# 功能：金币不足时，让数字短暂变红并弹动。
func play_not_enough_feedback() -> void:
	error_sound.play()
	amount_label.pivot_offset = amount_label.size * 0.5
	amount_label.modulate = Color(1.0, 0.35, 0.25, 1.0)
	amount_label.scale = Vector2.ONE

	var tween := create_tween()
	tween.tween_property(
		amount_label,
		"scale",
		Vector2(1.18, 1.18),
		0.08
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		amount_label,
		"scale",
		Vector2.ONE,
		0.10
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(
		amount_label,
		"modulate",
		Color.WHITE,
		0.18
	)
