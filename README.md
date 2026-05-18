# godot-D_Lifesaver

[English](README.md) | [日本語](README.ja.md)

A Godot editor plugin that provides a "Life Saver" button in the toolbar to quickly stage and commit all changes to git. Never lose your progress again with one-click temporary backups.

![Life Saver Button](doc_images/life_saver_button.jpg)

## Features

- **One-Click Backup**: Stages all changes (`git add -A`) and creates a temporary commit with a timestamped message (`d_lifesaver: auto-save ...`).
- **Shortcut Trigger**: Use `Ctrl + Alt + S` (customizable) to backup instantly without using the mouse.
- **Visual Status Indicators**:
  - **Safe (Green)**: Automatically detects when there are no changes to save. Displays `(Safe)`.
  - **Warning (Red)**: Turns red if more than 10 minutes have passed since your last save to remind you to back up.
- **Elapsed Time Display**: Shows how long ago your last commit was directly on the button (e.g., `15m`). Shows `< 1m` for the first minute to reduce visual noise.
- **Commit Counter**: Displays the total count of temporary commits (`x3`, `x5`, etc.) on the button.
- **Branch Visibility**: See the current git branch name in the button's tooltip.
- **Toast Notifications**: Provides immediate visual feedback for every action and error.
- **Configurable**: Polling intervals and shortcut keys can be adjusted in **Editor Settings**.

## Installation

1. Copy the `addons/godot-d_lifesaver` directory into your project's `res://addons/` folder.
2. Enable the plugin in **Project > Project Settings > Plugins**.

## Configuration

Go to **Editor > Editor Settings > d_lifesaver** to adjust:
- **Intervals**:
  - `Dirty Check Seconds`: Frequency of checking for unsaved changes (Default: 2s).
  - `Commit Count Seconds`: Frequency of updating the temporary commit count (Default: 60s).
- **Shortcut**:
  - `Trigger`: Key combination to trigger the backup (Default: `Ctrl+Alt+S`).
