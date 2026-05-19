@tool
class_name DLifesaverGit
extends RefCounted

## Helper class specialized for Git operations.

# ------------- [Constants] -------------
const PREFIX = "d_lifesaver:"


# ------------- [Public Static Method] -------------
## Check if current directory is inside a Git repository.
static func is_repo() -> bool:
	var output: Array = []
	var exit_code := OS.execute("git", ["rev-parse", "--is-inside-work-tree"], output)
	return exit_code == 0


## Get the Unix timestamp of the last commit.
static func get_last_commit_unix_time() -> int:
	var output: Array = []
	var exit_code := OS.execute("git", ["log", "-1", "--format=%ct"], output)
	if exit_code == 0 and not output.is_empty():
		return int(output[0])
	return 0


## Count the number of life-save commits in current branch.
static func get_auto_save_commit_count() -> int:
	var output: Array = []
	var exit_code := OS.execute("git", ["rev-list", "--count", "--grep=^" + PREFIX, "HEAD"], output)
	if exit_code == 0 and not output.is_empty():
		return int(output[0])
	return 0


## Get the current Git branch name.
static func get_current_branch() -> String:
	var output: Array = []
	var exit_code := OS.execute("git", ["branch", "--show-current"], output)
	if exit_code == 0 and not output.is_empty():
		return output[0].strip_edges()
	return "unknown"


## Check if there are any uncommitted changes (Dirty).
static func is_dirty() -> bool:
	var output: Array = []
	var exit_code := OS.execute("git", ["status", "--porcelain"], output)
	if exit_code == 0 and not output.is_empty():
		return not output[0].strip_edges().is_empty()
	return false


## Get the history of recent save messages.
static func get_recent_save_messages(count: int) -> PackedStringArray:
	var output: Array = []
	var exit_code := OS.execute(
		"git", ["log", "-n", str(count), "--grep=^" + PREFIX, "--format=%s"], output
	)
	if exit_code != 0 or output.is_empty():
		return []

	var lines: PackedStringArray = output[0].strip_edges().split("\n")
	var result: PackedStringArray = []
	for line in lines:
		if line.is_empty():
			continue
		result.append("- " + line.replace(PREFIX + " ", ""))
	return result


## Stage all changes and create a temporary commit.
static func save(custom_msg: String = "") -> Dictionary:
	var output: Array = []

	# Stage all changes
	var exit_code := OS.execute("git", ["add", "-A"], output)
	if exit_code != 0:
		return {"success": false, "error": "git add failed (code %d)" % exit_code}

	# Check for actual changes to commit
	output.clear()
	exit_code = OS.execute("git", ["diff", "--cached", "--quiet"], output)
	if exit_code == 0:
		return {"success": true, "changed": false}

	# Create the commit
	var time := Time.get_datetime_string_from_system().replace("T", " ")
	var commit_msg: String
	if custom_msg.is_empty():
		commit_msg = PREFIX + " auto-save " + time
	else:
		commit_msg = PREFIX + " " + custom_msg + " (" + time + ")"

	output.clear()
	exit_code = OS.execute("git", ["commit", "-m", commit_msg], output)

	if exit_code == 0:
		return {"success": true, "changed": true, "message": commit_msg}
	return {"success": false, "error": "git commit failed (code %d)" % exit_code}


## Remove the most recent life-save commit while keeping changes.
static func undo() -> Dictionary:
	# Verify if the HEAD commit belongs to us
	var output: Array = []
	var exit_code := OS.execute("git", ["log", "-1", "--format=%s"], output)
	if exit_code != 0 or output.is_empty():
		return {"success": false, "error": "Failed to check last commit"}

	var last_msg: String = output[0].strip_edges()
	if not last_msg.begins_with(PREFIX):
		return {"success": false, "error": "Last commit is not a life-save commit!"}

	# Revert using soft reset
	output.clear()
	exit_code = OS.execute("git", ["reset", "--soft", "HEAD~1"], output)

	if exit_code == 0:
		return {"success": true}
	return {"success": false, "error": "git reset failed (code %d)" % exit_code}


## Squash multiple temporary commits into a single refined commit.
static func squash() -> Dictionary:
	# Count how many sequential commits to squash
	var output: Array = []
	var exit_code := OS.execute("git", ["log", "--format=%s", "HEAD"], output)
	if exit_code != 0 or output.is_empty():
		return {"success": false, "error": "Failed to get git log"}

	var lines: PackedStringArray = output[0].split("\n")
	var squash_count: int = 0
	for line in lines:
		if line.begins_with(PREFIX):
			squash_count += 1
		else:
			break

	if squash_count <= 0:
		return {"success": true, "count": 0}

	# Perform soft reset to the base commit
	output.clear()
	exit_code = OS.execute("git", ["reset", "--soft", "HEAD~" + str(squash_count)], output)
	if exit_code != 0:
		return {"success": false, "error": "git reset failed (code %d)" % exit_code}

	# Create a refined commit
	var time := Time.get_datetime_string_from_system().replace("T", " ")
	var commit_msg := "Refined: sessions until " + time
	output.clear()
	exit_code = OS.execute("git", ["commit", "-m", commit_msg], output)

	if exit_code == 0:
		return {"success": true, "count": squash_count, "message": commit_msg}
	return {"success": false, "error": "git commit failed (code %d)" % exit_code}
