@tool
extends EditorPlugin

# ------------- [Private Variable] -------------
var _btn: Button
var _current_toast: PanelContainer
var _last_save_unix: int = 0
var _update_timer: float = 0.0
var _count_timer: float = 0.0
var _is_dirty: bool = false
var _commit_count: int = 0


# ------------- [Callbacks] -------------
func _enter_tree() -> void:
	_prepare_toolbar()


func _exit_tree() -> void:
	if _btn:
		remove_control_from_container(CONTAINER_TOOLBAR, _btn)
		_btn.queue_free()


func _process(delta: float) -> void:
	_update_timer += delta
	_count_timer += delta

	# Check git status and update text every 2 seconds
	if _update_timer >= 2.0:
		_update_timer = 0.0
		_is_dirty = _check_is_dirty()
		_update_button_text()
	
	# Update commit count every 60 seconds
	if _count_timer >= 60.0:
		_count_timer = 0.0
		_commit_count = _get_auto_save_commit_count()
		_update_button_text()


# ------------- [Private Method] -------------
func _prepare_toolbar() -> void:
	_btn = Button.new()
	_btn.tooltip_text = "Stage all changes and create a temporary commit"
	_btn.icon = get_editor_interface().get_base_control().get_theme_icon(&"Save", &"EditorIcons")
	_btn.pressed.connect(_on_btn_pressed)

	add_control_to_container(CONTAINER_TOOLBAR, _btn)

	_last_save_unix = _get_last_commit_unix_time()
	_is_dirty = _check_is_dirty()
	_commit_count = _get_auto_save_commit_count()
	_update_button_text()


func _get_last_commit_unix_time() -> int:
	var output: Array = []
	var exit_code := OS.execute("git", ["log", "-1", "--format=%ct"], output)
	if exit_code == 0 and not output.is_empty():
		return int(output[0])
	return 0


func _get_auto_save_commit_count() -> int:
	var output: Array = []
	# Count commits starting with our prefix
	var exit_code := OS.execute("git", ["rev-list", "--count", "--grep=^d_lifesaver:", "HEAD"], output)
	if exit_code == 0 and not output.is_empty():
		return int(output[0])
	return 0


func _check_is_dirty() -> bool:
	var output: Array = []
	# Check for any changes (staged or unstaged)
	var exit_code := OS.execute("git", ["status", "--porcelain"], output)
	if exit_code == 0 and not output.is_empty():
		return not output[0].strip_edges().is_empty()
	return false


func _update_button_text() -> void:
	if not is_instance_valid(_btn):
		return

	var base_text := "Life Saver"
	var count_text := " x{n}".format({"n": _commit_count}) if _commit_count > 0 else ""

	if not _is_dirty:
		_btn.text = "{base} (Safe{count})".format({"base": base_text, "count": count_text})
		_btn.add_theme_color_override("font_color", Color.MEDIUM_SEA_GREEN)
		_btn.add_theme_color_override("font_hover_color", Color.MEDIUM_SEA_GREEN.lightened(0.2))
		_btn.add_theme_color_override("font_pressed_color", Color.MEDIUM_SEA_GREEN.darkened(0.2))
		_btn.add_theme_color_override("font_focus_color", Color.MEDIUM_SEA_GREEN)
		return

	if _last_save_unix <= 0:
		_btn.text = base_text + count_text
		_btn.remove_theme_color_override("font_color")
		return

	var now := int(Time.get_unix_time_from_system())
	var elapsed := now - _last_save_unix
	
	# Update text
	_btn.text = "{base} ({time}{count})".format({
		"base": base_text, 
		"time": _format_elapsed_time(elapsed),
		"count": count_text
	})
	
	# Update color: turn red if > 10 minutes (600 seconds)
	if elapsed >= 600:
		_btn.add_theme_color_override("font_color", Color.INDIAN_RED)
		_btn.add_theme_color_override("font_hover_color", Color.INDIAN_RED.lightened(0.2))
		_btn.add_theme_color_override("font_pressed_color", Color.INDIAN_RED.darkened(0.2))
		_btn.add_theme_color_override("font_focus_color", Color.INDIAN_RED)
	else:
		_btn.remove_theme_color_override("font_color")
		_btn.remove_theme_color_override("font_hover_color")
		_btn.remove_theme_color_override("font_pressed_color")
		_btn.remove_theme_color_override("font_focus_color")


func _format_elapsed_time(seconds: int) -> String:
	if seconds < 60:
		return "< 1m"
	if seconds < 3600:
		return "{m}m".format({"m": seconds / 60})
	if seconds < 86400:
		return "{h}h".format({"h": seconds / 3600})
	return "{d}d".format({"d": seconds / 86400})


func _on_btn_pressed() -> void:
	DLogger.info("Saving your life...")
	_show_toast("Saving your life...")
	_git_save()


func _git_save() -> void:
	var output: Array = []

	# 1. Stage all changes
	var exit_code := OS.execute("git", ["add", "-A"], output)
	if exit_code != 0:
		var err_msg := "git add failed (code {code})".format({"code": exit_code})
		DLogger.error(err_msg)
		_show_toast(err_msg, true)
		return

	# 2. Check for changes
	output.clear()
	exit_code = OS.execute("git", ["diff", "--cached", "--quiet"], output)
	if exit_code == 0:
		DLogger.info("Nothing to save.")
		_show_toast("Nothing to save.")
		_is_dirty = false
		_update_button_text()
		return

	# 3. Commit
	var time := Time.get_datetime_string_from_system().replace("T", " ")
	var commit_msg := "d_lifesaver: auto-save " + time
	output.clear()
	exit_code = OS.execute("git", ["commit", "-m", commit_msg], output)

	if exit_code == 0:
		DLogger.info("Life saved! " + commit_msg)
		_show_toast("Life saved!\n" + commit_msg)
		_last_save_unix = int(Time.get_unix_time_from_system())
		_is_dirty = false
		_commit_count = _get_auto_save_commit_count()
		_update_button_text()
	else:
		var err_msg := "git commit failed (code {code})".format({"code": exit_code})
		DLogger.error(err_msg)
		_show_toast(err_msg, true)


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
	tween.finished.connect(
		func(): if is_instance_valid(panel) and _current_toast == panel: _current_toast = null
	)
