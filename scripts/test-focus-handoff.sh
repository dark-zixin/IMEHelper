#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
if ! command -v rg >/dev/null 2>&1; then
  print -u2 '缺少 rg，無法確認焦點交接測試結果'
  exit 2
fi
log_dir="$repo_root/tmp/topics/11070447_focus_handoff/log"
mkdir -p "$log_dir"

module_cache="$log_dir/swift-module-cache"
injector_binary="$log_dir/focus-injector-tests"
panel_binary="$log_dir/focus-panel-tests"

swiftc -swift-version 5 -default-isolation MainActor -module-cache-path "$module_cache" \
  "$repo_root/IMEHelper/TextInjector.swift" \
  "$repo_root/Tests/FocusHandoff/InjectorRunner.swift" \
  -o "$injector_binary"

if ! "$injector_binary" > "$log_dir/injector-tests.log" 2>&1; then
  cat "$log_dir/injector-tests.log"
  exit 1
fi

swiftc -swift-version 5 -default-isolation MainActor -module-cache-path "$module_cache" \
  "$repo_root/IMEHelper/HotkeyManager.swift" \
  "$repo_root/IMEHelper/InputTextView.swift" \
  "$repo_root/IMEHelper/InputPanel.swift" \
  "$repo_root/IMEHelper/SettingsManager.swift" \
  "$repo_root/IMEHelper/SourceAppInfo.swift" \
  "$repo_root/IMEHelper/EscStateMachine.swift" \
  "$repo_root/Tests/FocusHandoff/PanelRunner.swift" \
  -o "$panel_binary"

if ! "$panel_binary" > "$log_dir/panel-tests.log" 2>&1; then
  cat "$log_dir/panel-tests.log"
  exit 1
fi

rg '^PASS：' "$log_dir/injector-tests.log" "$log_dir/panel-tests.log"
