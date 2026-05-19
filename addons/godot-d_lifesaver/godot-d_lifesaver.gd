## Main class for the Life Saver plugin.
## Manages UI controls and triggers Git operations.
@tool
extends EditorPlugin

# ------------- [Constants] -------------
const SETTING_DIRTY_CHECK_INTERVAL = "d_lifesaver/intervals/dirty_check_seconds"
const SETTING_COMMIT_COUNT_INTERVAL = "d_lifesaver/intervals/commit_count_seconds"
const SETTING_SHORTCUT = "d_lifesaver/shortcut/trigger"
const SETTING_AUTO_SAVE_ON_FOCUS_LOSS = "d_lifesaver/auto_save/on_focus_loss"

# ------------- [Private Variable] -------------
var _btn: Button
var _squash_btn: Button
var _undo_btn: Button
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
	if _undo_btn:
		remove_control_from_container(CONTAINER_TOOLBAR, _undo_btn)
		_undo_btn.queue_free()
	if _commit_dialog:
		_commit_dialog.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		var es := get_editor_interface().get_editor_settings()
		if (
			es.has_setting(SETTING_AUTO_SAVE_ON_FOCUS_LOSS)
			and es.get_setting(SETTING_AUTO_SAVE_ON_FOCUS_LOSS)
		):
			if _is_git_repo and _is_dirty:
				DLogger.info("Auto-saving on focus loss...")
				_trigger_git_save()


func _input(event: InputEvent) -> void:
	if not _is_git_repo:
		return

	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return

	var es := get_editor_interface().get_editor_settings()
	var shortcut_text: String = es.get_setting(SETTING_SHORTCUT)
	if shortcut_text.is_empty():
		return

	if event.as_text() == shortcut_text:
		_on_btn_pressed()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Check for repo initialization periodically if not already detected
	if not _is_git_repo:
		_git_check_timer += delta
		if _git_check_timer >= 5.0:
			_git_check_timer = 0.0
			_is_git_repo = DLifesaverGit.is_repo()
			if _is_git_repo:
				DLogger.info("Git repository detected. Life Saver is now active.")
				_show_toast("Git repository detected!\nLife Saver is now active.")
				_on_git_initialized()
			_update_ui()
		return

	_update_timer += delta
	_count_timer += delta

	var es := get_editor_interface().get_editor_settings()
	var dirty_interval: float = es.get_setting(SETTING_DIRTY_CHECK_INTERVAL)
	var count_interval: float = es.get_setting(SETTING_COMMIT_COUNT_INTERVAL)

	# Update status periodically
	if _update_timer >= dirty_interval:
		_update_timer = 0.0
		_is_dirty = DLifesaverGit.is_dirty()
		_current_branch = DLifesaverGit.get_current_branch()
		_update_ui()

	# Update commit count periodically
	if _count_timer >= count_interval:
		_count_timer = 0.0
		_commit_count = DLifesaverGit.get_auto_save_commit_count()
		_update_ui()


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

	if not es.has_setting(SETTING_AUTO_SAVE_ON_FOCUS_LOSS):
		es.set_setting(SETTING_AUTO_SAVE_ON_FOCUS_LOSS, false)
	(
		es
		. add_property_info(
			{
				"name": SETTING_AUTO_SAVE_ON_FOCUS_LOSS,
				"type": TYPE_BOOL,
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


func _prepare_toolbar() -> void:
	var base_control := get_editor_interface().get_base_control()

	_btn = Button.new()
	_btn.icon = base_control.get_theme_icon(&"Save", &"EditorIcons")
	_btn.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	_btn.gui_input.connect(_on_btn_gui_input)
	_btn.pressed.connect(_on_btn_pressed)

	_squash_btn = Button.new()
	_squash_btn.icon = base_control.get_theme_icon(&"AssetLib", &"EditorIcons")
	_squash_btn.tooltip_text = "Squash all temporary commits into one"
	_squash_btn.pressed.connect(_on_squash_pressed)

	_undo_btn = Button.new()
	_undo_btn.icon = base_control.get_theme_icon(&"Back", &"EditorIcons")
	_undo_btn.tooltip_text = "Undo last life-save commit"
	_undo_btn.pressed.connect(_on_undo_pressed)

	add_control_to_container(CONTAINER_TOOLBAR, _btn)
	add_control_to_container(CONTAINER_TOOLBAR, _squash_btn)
	add_control_to_container(CONTAINER_TOOLBAR, _undo_btn)

	_is_git_repo = DLifesaverGit.is_repo()
	if _is_git_repo:
		_on_git_initialized()
	else:
		_update_ui()


func _on_git_initialized() -> void:
	_last_save_unix = DLifesaverGit.get_last_commit_unix_time()
	_is_dirty = DLifesaverGit.is_dirty()
	_current_branch = DLifesaverGit.get_current_branch()
	_commit_count = DLifesaverGit.get_auto_save_commit_count()
	_update_ui()


func _update_ui() -> void:
	if (
		not is_instance_valid(_btn)
		or not is_instance_valid(_squash_btn)
		or not is_instance_valid(_undo_btn)
	):
		return

	var base_text := "Life Saver"

	if not _is_git_repo:
		_btn.text = base_text + " (No Git)"
		_btn.disabled = true
		_btn.tooltip_text = "Git is not initialized in this project."
		_btn.remove_theme_color_override("font_color")
		_squash_btn.visible = false
		_undo_btn.visible = false
		return

	_btn.disabled = false
	var count_text := " x%d" % _commit_count if _commit_count > 0 else ""
	var has_temp_commits := _commit_count > 0
	var branch_prefix := "[%s] " % _current_branch

	# Update Squash & Undo visibility
	_squash_btn.visible = has_temp_commits
	_squash_btn.tooltip_text = "Squash %d temporary commits" % _commit_count
	_undo_btn.visible = has_temp_commits

	# Generate tooltip with history
	var es := get_editor_interface().get_editor_settings()
	var shortcut_val: Variant = es.get_setting(SETTING_SHORTCUT)
	var shortcut_str: String = str(shortcut_val) if shortcut_val != null else "None"
	var history := DLifesaverGit.get_recent_save_messages(3)
	var history_text := "\n\nRecent Saves:\n" + "\n".join(history) if not history.is_empty() else ""

	_btn.tooltip_text = (
		"L-Click: Quick Save\nR-Click: Memo & Save\nShortcut: %s\nBranch: %s%s"
		% [shortcut_str, _current_branch, history_text]
	)

	# Handle status text and colors
	if not _is_dirty:
		_btn.text = "%s%s (Safe%s)" % [branch_prefix, base_text, count_text]
		_btn.add_theme_color_override("font_color", Color.MEDIUM_SEA_GREEN)
		_btn.self_modulate = Color.WHITE
		return

	_btn.self_modulate = Color(1.0, 0.75, 0.3)  # Subdued Amber

	if _last_save_unix <= 0:
		_btn.text = branch_prefix + base_text + count_text
		_btn.remove_theme_color_override("font_color")
		return

	var elapsed := int(Time.get_unix_time_from_system()) - _last_save_unix
	_btn.text = (
		"%s%s (%s%s)" % [branch_prefix, base_text, _format_elapsed_time(elapsed), count_text]
	)

	# Turn red if more than 10 minutes have passed
	if elapsed >= 600:
		_btn.add_theme_color_override("font_color", Color.INDIAN_RED)
	else:
		_btn.remove_theme_color_override("font_color")


func _format_elapsed_time(seconds: int) -> String:
	if seconds < 60:
		return "< 1m"
	if seconds < 3600:
		return "%dm" % (seconds / 60)
	if seconds < 86400:
		return "%dh" % (seconds / 3600)
	return "%dd" % (seconds / 86400)


func _show_toast(text: String, is_error: bool = false) -> void:
	if _current_toast:
		_current_toast.queue_free()

	var base := get_editor_interface().get_base_control()
	var panel := PanelContainer.new()
	_current_toast = panel
	var label := Label.new()

	label.text = text
	panel.add_child(label)
	panel.add_theme_stylebox_override("panel", base.get_theme_stylebox(&"panel", &"TooltipPanel"))
	label.add_theme_color_override(
		"font_color",
		Color.INDIAN_RED if is_error else base.get_theme_color(&"font_color", &"TooltipLabel")
	)

	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.top_level = true
	base.add_child(panel)

	await get_tree().process_frame
	if not is_instance_valid(panel):
		return

	panel.position = Vector2((base.size.x - panel.size.x) / 2.0, base.size.y - panel.size.y - 100.0)
	var tween := panel.create_tween()
	panel.modulate.a = 0.0
	tween.tween_property(panel, "modulate:a", 1.0, 0.1)
	tween.tween_interval(2.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func _trigger_git_save(custom_msg: String = "") -> void:
	var result := DLifesaverGit.save(custom_msg)
	if result.success:
		if result.changed:
			DLogger.info("Life saved! " + result.message)
			_show_toast("Life saved!\n" + result.message)
			_last_save_unix = int(Time.get_unix_time_from_system())
		else:
			DLogger.info("Nothing to save.")
			_show_toast("Nothing to save.")
		_on_git_initialized()
	else:
		DLogger.error(result.error)
		_show_toast(result.error, true)


# ------------- [Callbacks] -------------
func _on_commit_dialog_confirmed() -> void:
	var msg: String = _commit_line_edit.text.strip_edges()
	_commit_line_edit.text = ""
	_trigger_git_save(msg)


func _on_commit_line_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and event.ctrl_pressed:
			_commit_dialog.hide()
			_on_commit_dialog_confirmed()
			get_viewport().set_input_as_handled()


func _on_undo_pressed() -> void:
	var result := DLifesaverGit.undo()
	if result.success:
		DLogger.info("Undo successful.")
		_show_toast("Undo successful!")
		_on_git_initialized()
	else:
		_show_toast(result.error, true)


func _on_squash_pressed() -> void:
	if _commit_count <= 0:
		return
	DLogger.info("Squashing %d commits..." % _commit_count)

	var result := DLifesaverGit.squash()
	if result.success:
		DLogger.info("Squashed! " + result.message)
		_show_toast("Squashed %d commits into one!" % result.count)
		_on_git_initialized()
	else:
		_show_toast(result.error, true)


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
	_trigger_git_save()
