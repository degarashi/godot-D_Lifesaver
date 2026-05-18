@tool
extends EditorPlugin

# ------------- [Private Variable] -------------
var _btn: Button


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

	var output: Array = []

	# git add -A
	var exit_code := OS.execute("git", ["add", "-A"], output)
	if exit_code != 0:
		DLogger.error("git add -A failed with exit code {0}", [exit_code])
		for line in output:
			DLogger.error(line)
		return

	# Check if there are staged changes to commit
	output.clear()
	exit_code = OS.execute("git", ["diff", "--cached", "--quiet"], output)
	if exit_code == 0:
		DLogger.info("Nothing to save. Your life is already safe.")
		return

	# git commit -m "..."
	var time := Time.get_datetime_string_from_system().replace("T", " ")
	var commit_msg := "d_lifesaver: auto-save " + time
	output.clear()
	exit_code = OS.execute("git", ["commit", "-m", commit_msg], output)

	if exit_code == 0:
		DLogger.info("Life saved! Commit: " + commit_msg)
	else:
		DLogger.error("git commit failed with exit code {0}", [exit_code])
		for line in output:
			DLogger.error(line)
