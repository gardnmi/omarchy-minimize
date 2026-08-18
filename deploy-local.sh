#!/bin/bash

set -euo pipefail

plugin_dir="$HOME/.config/omarchy/plugins/io.github.gardnmi.window-shelf"
session_omarchy_path=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${session_omarchy_path:=${OMARCHY_PATH:-/usr/share/omarchy}}"
shell_dir="$session_omarchy_path/shell"

[[ -f $shell_dir/shell.qml ]] || { echo "Omarchy shell config not found: $shell_dir" >&2; exit 1; }

# Avoid Quickshell's plugin-reload race by updating the plugin only after the
# current shell has fully exited. omarchy restart shell starts it again below.
while timeout 5 quickshell kill -p "$shell_dir" --any-display >/dev/null 2>&1; do :; done

install -d "$plugin_dir"
install -m 644 BarWidget.qml README.md manifest.json "$plugin_dir/"

omarchy restart shell
