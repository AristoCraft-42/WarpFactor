class_name ToastStack
extends VBoxContainer
## Всплывающие уведомления сверху по центру. Каждое плавно исчезает через несколько секунд.

const LIFETIME := 3.2
const MAX_TOASTS := 5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 6)
	Events.toast_requested.connect(show_toast)


func show_toast(text: String, kind: Events.ToastKind = Events.ToastKind.INFO) -> void:
	while get_child_count() >= MAX_TOASTS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var accent := UiTheme.FG
	match kind:
		Events.ToastKind.SUCCESS:
			accent = UiTheme.GREEN
		Events.ToastKind.WARNING:
			accent = UiTheme.ORANGE
	var style := (panel.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.border_color = accent
	style.border_width_left = 4
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	panel.add_child(label)
	add_child(panel)

	var tween := panel.create_tween()
	tween.tween_interval(LIFETIME)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
