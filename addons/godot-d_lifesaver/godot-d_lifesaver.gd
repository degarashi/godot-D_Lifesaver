@tool
extends EditorPlugin

# ------------- [Private Variable] -------------
var _btn: Button
var _current_toast: PanelContainer


# ------------- [Callbacks] -------------
func _enter_tree() -> void:
	_prepare_button()


func _exit_tree() -> void:
	if _btn:
		remove_control_from_container(CONTAINER_TOOLBAR, _btn)
		_btn.queue_free()


# ------------- [Private Method] -------------
func _prepare_button() -> void:
	_btn = Button.new()
	_btn.text = "Life Saver"
	_btn.tooltip_text = "Stage all changes and create a temporary commit"

	# Get a built-in icon if possible. "Save" is a good fallback.
	# Wait, we need to wait until the editor is ready to get theme icons reliably.
	# But in _enter_tree of a plugin, it's usually fine or we can use a callback.
	_btn.icon = get_editor_interface().get_base_control().get_theme_icon(&"Save", &"EditorIcons")

	_btn.pressed.connect(_on_btn_pressed)
	add_control_to_container(CONTAINER_TOOLBAR, _btn)


func _on_btn_pressed() -> void:
	DLogger.info("Saving your life...")
	_show_toast("Saving your life...")

	var output: Array = []

	# git add -A
	var exit_code := OS.execute("git", ["add", "-A"], output)
	if exit_code != 0:
		var err_msg := "git add -A failed (code {0})".format([exit_code])
		DLogger.error(err_msg)
		_show_toast(err_msg, true)
		for line in output:
			DLogger.error(line)
		return

	# Check if there are staged changes to commit
	output.clear()
	exit_code = OS.execute("git", ["diff", "--cached", "--quiet"], output)
	if exit_code == 0:
		DLogger.info("Nothing to save. Your life is already safe.")
		_show_toast("Nothing to save. Your life is already safe.")
		return

	# git commit -m "..."
	var time := Time.get_datetime_string_from_system().replace("T", " ")
	var commit_msg := "d_lifesaver: auto-save " + time
	output.clear()
	exit_code = OS.execute("git", ["commit", "-m", commit_msg], output)

	if exit_code == 0:
		DLogger.info("Life saved! Commit: " + commit_msg)
		_show_toast("Life saved! \n" + commit_msg)
	else:
		var err_msg := "git commit failed (code {0})".format(exit_code)
		DLogger.error(err_msg)
		_show_toast(err_msg, true)
		for line in output:
			DLogger.error(line)


func _show_toast(text: String, is_error: bool = false) -> void:
	if _current_toast:
		_current_toast.queue_free()
		_current_toast = null

	var base := get_editor_interface().get_base_control()
	var panel := PanelContainer.new()
	_current_toast = panel
	var label := Label.new()

	label.text = text
	panel.add_child(label)

	# Apply theme
	var theme_base := &"TooltipPanel"
	var font_base := &"TooltipLabel"

	panel.add_theme_stylebox_override("panel", base.get_theme_stylebox(&"panel", theme_base))
	label.add_theme_font_override("font", base.get_theme_font(&"font", font_base))
	label.add_theme_font_size_override(
		"font_size", base.get_theme_font_size(&"font_size", font_base)
	)

	if is_error:
		label.add_theme_color_override("font_color", Color.INDIAN_RED)
	else:
		label.add_theme_color_override("font_color", base.get_theme_color(&"font_color", font_base))

	# Positioning and overlay
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.top_level = true  # Make it independent of parent transform
	base.add_child(panel)

	# Center it at the bottom
	await get_tree().process_frame  # Wait for size to be calculated
	if not is_instance_valid(panel):
		return

	var base_size := base.size
	var panel_size := panel.size
	panel.position = Vector2((base_size.x - panel_size.x) / 2.0, base_size.y - panel_size.y - 100.0)

	# Animation
	var tween := panel.create_tween()
	panel.modulate.a = 0.0
	tween.tween_property(panel, "modulate:a", 1.0, 0.1)
	tween.tween_interval(2.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
	tween.finished.connect(func(): if is_instance_valid(panel) and _current_toast == panel: _current_toast = null)
