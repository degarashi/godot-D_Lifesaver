@tool
extends EditorPlugin

# ------------- [Constants] -------------
const SETTING_DIRTY_CHECK_INTERVAL = "d_lifesaver/intervals/dirty_check_seconds"
const SETTING_COMMIT_COUNT_INTERVAL = "d_lifesaver/intervals/commit_count_seconds"
const SETTING_SHORTCUT = "d_lifesaver/shortcut/trigger"

# ------------- [Private Variable] -------------
var _btn: Button
var _squash_btn: Button
var _commit_dialog: ConfirmationDialog
var _commit_line_edit: LineEdit
var _current_toast: PanelContainer
var _last_save_unix: int = 0
var _update_timer: float = 0.0
var _count_timer: float = 0.0
var _git_check_timer: float = 0.0
var _is_dirty: bool = false
var _commit_count: int = 0
var _current_branch: String = "unknown"
var _is_git_repo: bool = false


# ------------- [Callbacks] -------------
func _enter_tree() -> void:
	_prepare_preferences()
	_prepare_commit_dialog()
	_prepare_toolbar()


func _exit_tree() -> void:
	if _btn:
		remove_control_from_container(CONTAINER_TOOLBAR, _btn)
		_btn.queue_free()
	if _squash_btn:
		remove_control_from_container(CONTAINER_TOOLBAR, _squash_btn)
		_squash_btn.queue_free()
	if _commit_dialog:
		_commit_dialog.queue_free()


func _input(event: InputEvent) -> void:
	if not _is_git_repo:
		return

	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return

	var es := get_editor_interface().get_editor_settings()
	var shortcut_text: String = es.get_setting(SETTING_SHORTCUT)
	if shortcut_text.is_empty():
		return

	# Simple shortcut matching
	if event.as_text() == shortcut_text:
		_on_btn_pressed()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# If not a git repo, check less frequently if it has been initialized
	if not _is_git_repo:
		_git_check_timer += delta
		if _git_check_timer >= 5.0:
			_git_check_timer = 0.0
			_is_git_repo = _check_is_git_repo()
			if _is_git_repo:
				DLogger.info("Git repository detected. Life Saver is now active.")
				_show_toast("Git repository detected!\nLife Saver is now active.")
				_on_git_initialized()
			_update_button_text()
		return

	_update_timer += delta
	_count_timer += delta

	var es := get_editor_interface().get_editor_settings()
	var dirty_interval: float = es.get_setting(SETTING_DIRTY_CHECK_INTERVAL)
	var count_interval: float = es.get_setting(SETTING_COMMIT_COUNT_INTERVAL)

	# Check git status and update text
	if _update_timer >= dirty_interval:
		_update_timer = 0.0
		_is_dirty = _check_is_dirty()
		_current_branch = _get_current_branch()
		_update_button_text()

	# Update commit count
	if _count_timer >= count_interval:
		_count_timer = 0.0
		_commit_count = _get_auto_save_commit_count()
		_update_button_text()


# ------------- [Private Method] -------------
func _prepare_preferences() -> void:
	var es := get_editor_interface().get_editor_settings()

	if not es.has_setting(SETTING_DIRTY_CHECK_INTERVAL):
		es.set_setting(SETTING_DIRTY_CHECK_INTERVAL, 2.0)
	es.add_property_info(
		{
			"name": SETTING_DIRTY_CHECK_INTERVAL,
			"type": TYPE_FLOAT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "0.5,60,0.5"
		}
	)

	if not es.has_setting(SETTING_COMMIT_COUNT_INTERVAL):
		es.set_setting(SETTING_COMMIT_COUNT_INTERVAL, 60.0)
	es.add_property_info(
		{
			"name": SETTING_COMMIT_COUNT_INTERVAL,
			"type": TYPE_FLOAT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "5,600,1"
		}
	)

	if not es.has_setting(SETTING_SHORTCUT):
		# Default shortcut
		es.set_setting(SETTING_SHORTCUT, "Ctrl+Alt+S")
	(
		es
		. add_property_info(
			{
				"name": SETTING_SHORTCUT,
				"type": TYPE_STRING,
			}
		)
	)


func _prepare_commit_dialog() -> void:
	_commit_dialog = ConfirmationDialog.new()
	_commit_dialog.title = "Life Saver: Commit Message"
	_commit_dialog.confirmed.connect(_on_commit_dialog_confirmed)

	var vbox := VBoxContainer.new()
	_commit_dialog.add_child(vbox)

	var label := Label.new()
	label.text = "Optional: Enter a memo for this save (prefix 'd_lifesaver:' will be added)"
	vbox.add_child(label)

	_commit_line_edit = LineEdit.new()
	_commit_line_edit.placeholder_text = "auto-save (default)"
	_commit_line_edit.custom_minimum_size.x = 400
	vbox.add_child(_commit_line_edit)

	_commit_dialog.register_text_enter(_commit_line_edit)

	get_editor_interface().get_base_control().add_child(_commit_dialog)


func _on_commit_dialog_confirmed() -> void:
	var msg: String = _commit_line_edit.text.strip_edges()
	_commit_line_edit.text = ""  # Clear for next time
	_git_save(msg)


func _prepare_toolbar() -> void:
	_btn = Button.new()
	_btn.icon = get_editor_interface().get_base_control().get_theme_icon(&"Save", &"EditorIcons")
	# Allow both left and right clicks
	_btn.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	_btn.gui_input.connect(_on_btn_gui_input)
	_btn.pressed.connect(_on_btn_pressed)

	_squash_btn = Button.new()
	_squash_btn.icon = get_editor_interface().get_base_control().get_theme_icon(
		&"AssetLib", &"EditorIcons"
	)
	_squash_btn.tooltip_text = "Squash all temporary commits into one"
	_squash_btn.pressed.connect(_on_squash_pressed)

	add_control_to_container(CONTAINER_TOOLBAR, _btn)
	add_control_to_container(CONTAINER_TOOLBAR, _squash_btn)

	_is_git_repo = _check_is_git_repo()
	if _is_git_repo:
		_on_git_initialized()
	else:
		_update_button_text()


func _on_git_initialized() -> void:
	_last_save_unix = _get_last_commit_unix_time()
	_is_dirty = _check_is_dirty()
	_current_branch = _get_current_branch()
	_commit_count = _get_auto_save_commit_count()
	_update_button_text()


func _check_is_git_repo() -> bool:
	var output: Array = []
	var exit_code := OS.execute("git", ["rev-parse", "--is-inside-work-tree"], output)
	return exit_code == 0


func _get_last_commit_unix_time() -> int:
	var output: Array = []
	var exit_code := OS.execute("git", ["log", "-1", "--format=%ct"], output)
	if exit_code == 0 and not output.is_empty():
		return int(output[0])
	return 0


func _get_auto_save_commit_count() -> int:
	var output: Array = []
	# Count commits starting with our prefix
	var exit_code := OS.execute(
		"git", ["rev-list", "--count", "--grep=^d_lifesaver:", "HEAD"], output
	)
	if exit_code == 0 and not output.is_empty():
		return int(output[0])
	return 0


func _get_current_branch() -> String:
	var output: Array = []
	var exit_code := OS.execute("git", ["branch", "--show-current"], output)
	if exit_code == 0 and not output.is_empty():
		return output[0].strip_edges()
	return "unknown"


func _get_recent_save_messages(count: int) -> PackedStringArray:
	var output: Array = []
	var exit_code := OS.execute(
		"git", ["log", "-n", str(count), "--grep=^d_lifesaver:", "--format=%s"], output
	)
	if exit_code != 0 or output.is_empty():
		return []

	var lines: PackedStringArray = output[0].strip_edges().split("\n")
	var result: PackedStringArray = []
	for line in lines:
		if line.is_empty():
			continue
		# Remove the prefix for cleaner display
		result.append("- " + line.replace("d_lifesaver: ", ""))
	return result


func _check_is_dirty() -> bool:
	var output: Array = []
	# Check for any changes (staged or unstaged)
	var exit_code := OS.execute("git", ["status", "--porcelain"], output)
	if exit_code == 0 and not output.is_empty():
		return not output[0].strip_edges().is_empty()
	return false


func _update_button_text() -> void:
	if not is_instance_valid(_btn) or not is_instance_valid(_squash_btn):
		return

	var base_text := "Life Saver"

	if not _is_git_repo:
		_btn.text = "{base} (No Git)".format({"base": base_text})
		_btn.disabled = true
		_btn.tooltip_text = "Git is not initialized in this project.\nPlease run 'git init' to use Life Saver."
		_btn.remove_theme_color_override("font_color")

		_squash_btn.visible = false
		return

	_btn.disabled = false
	var count_text := " x{n}".format({"n": _commit_count}) if _commit_count > 0 else ""

	# Squash button visibility
	_squash_btn.visible = _commit_count > 0
	_squash_btn.tooltip_text = "Squash {n} temporary commits".format({"n": _commit_count})

	var es := get_editor_interface().get_editor_settings()
	var shortcut_val: Variant = es.get_setting(SETTING_SHORTCUT)
	var shortcut_str: String = str(shortcut_val) if shortcut_val != null else "None"

	var history := _get_recent_save_messages(3)
	var history_text := ""
	if not history.is_empty():
		history_text = "\n\nRecent Saves:\n" + "\n".join(history)

	_btn.tooltip_text = (
		"L-Click: Quick Save\nR-Click: Memo & Save\nShortcut: %s\nBranch: %s%s"
		% [shortcut_str, _current_branch, history_text]
	)

	if not _is_dirty:
		_btn.text = "{base} (Safe{count})".format({"base": base_text, "count": count_text})
		_btn.add_theme_color_override("font_color", Color.MEDIUM_SEA_GREEN)
		_btn.add_theme_color_override("font_hover_color", Color.MEDIUM_SEA_GREEN.lightened(0.2))
		_btn.add_theme_color_override("font_pressed_color", Color.MEDIUM_SEA_GREEN.darkened(0.2))
		_btn.add_theme_color_override("font_focus_color", Color.MEDIUM_SEA_GREEN)
		_btn.self_modulate = Color.WHITE
		return

	# Highlight icon when dirty (Subdued Amber)
	_btn.self_modulate = Color(1.0, 0.75, 0.3)

	if _last_save_unix <= 0:
		_btn.text = base_text + count_text
		_btn.remove_theme_color_override("font_color")
		_btn.remove_theme_color_override("font_hover_color")
		_btn.remove_theme_color_override("font_pressed_color")
		_btn.remove_theme_color_override("font_focus_color")
		return

	var now := int(Time.get_unix_time_from_system())
	var elapsed := now - _last_save_unix

	# Update text
	_btn.text = ("{base} ({time}{count})".format(
		{"base": base_text, "time": _format_elapsed_time(elapsed), "count": count_text}
	))

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


func _on_squash_pressed() -> void:
	if _commit_count <= 0:
		return

	# Confirmation (Using a simple toast for now, but in a real app might want a dialog)
	DLogger.info("Squashing {n} commits...".format({"n": _commit_count}))
	_git_squash()


func _git_squash() -> void:
	# Find the base commit (the first one NOT starting with d_lifesaver:)
	var output: Array = []
	var exit_code := OS.execute("git", ["log", "--format=%s", "HEAD"], output)
	if exit_code != 0 or output.is_empty():
		_show_toast("Failed to get git log", true)
		return

	var lines: PackedStringArray = output[0].split("\n")
	var squash_count: int = 0
	for line in lines:
		if line.begins_with("d_lifesaver:"):
			squash_count += 1
		else:
			break

	if squash_count <= 0:
		_show_toast("Nothing to squash.")
		return

	# Reset soft to HEAD~N
	output.clear()
	exit_code = OS.execute("git", ["reset", "--soft", "HEAD~" + str(squash_count)], output)
	if exit_code != 0:
		_show_toast("git reset failed", true)
		return

	# Create a new commit
	# We use a placeholder message, users can rename it later via git commit --amend
	var time := Time.get_datetime_string_from_system().replace("T", " ")
	var commit_msg := "Refined: sessions until " + time
	output.clear()
	exit_code = OS.execute("git", ["commit", "-m", commit_msg], output)

	if exit_code == 0:
		DLogger.info("Squashed! " + commit_msg)
		_show_toast("Squashed {n} commits into one!".format({"n": squash_count}))
		_commit_count = _get_auto_save_commit_count()
		_update_button_text()
	else:
		_show_toast("git commit failed", true)


func _on_btn_gui_input(event: InputEvent) -> void:
	if not _is_git_repo:
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		_btn.accept_event()
		_commit_line_edit.text = ""
		_commit_dialog.popup_centered()
		_commit_line_edit.grab_focus()


func _on_btn_pressed() -> void:
	if not _is_git_repo:
		_show_toast("Git is not initialized!", true)
		return

	# This is triggered by Left-Click (default Button behavior) or Shortcut
	_git_save()


func _git_save(custom_msg: String = "") -> void:
	var output: Array = []

	# Stage all changes
	var exit_code := OS.execute("git", ["add", "-A"], output)
	if exit_code != 0:
		var err_msg := "git add failed (code {code})".format({"code": exit_code})
		DLogger.error(err_msg)
		_show_toast(err_msg, true)
		return

	# Check for changes
	output.clear()
	exit_code = OS.execute("git", ["diff", "--cached", "--quiet"], output)
	if exit_code == 0:
		DLogger.info("Nothing to save.")
		_show_toast("Nothing to save.")
		_is_dirty = false
		_update_button_text()
		return

	# Commit
	var time := Time.get_datetime_string_from_system().replace("T", " ")
	var commit_msg: String
	if custom_msg.is_empty():
		commit_msg = "d_lifesaver: auto-save " + time
	else:
		commit_msg = "d_lifesaver: " + custom_msg + " (" + time + ")"

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
		func() -> void:
			if is_instance_valid(panel) and _current_toast == panel:
				_current_toast = null,
	)
