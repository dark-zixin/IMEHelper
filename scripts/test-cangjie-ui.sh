#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
if ! command -v rg >/dev/null 2>&1; then
  print -u2 '缺少 rg，無法確認 UI 測試結果'
  exit 2
fi
topic_dir="$repo_root/tmp/topics/11062140_cangjie_lookup/compact-v2"
log_dir="$topic_dir/log"
mkdir -p "$log_dir" "$topic_dir/native-shots"
app_path=${1:-"$repo_root/build/cangjie-derived/Build/Products/Debug/IMEHelper.app"}

swiftc -swift-version 5 -default-isolation MainActor -module-cache-path "$log_dir/swift-module-cache" \
  "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
  "$repo_root/IMEHelper/CangjieDictionary.swift" \
  "$repo_root/IMEHelper/CangjieSavedListStore.swift" \
  "$repo_root/IMEHelper/CangjieLookupTextView.swift" \
  "$repo_root/IMEHelper/CangjieLookupContentView.swift" \
  "$repo_root/IMEHelper/CangjieLookupWindowController.swift" \
  "$repo_root/Tests/CangjieUI/Runner.swift" \
  -o "$log_dir/cangjie-ui-tests"

"$log_dir/cangjie-ui-tests" "$repo_root" "$app_path" "$topic_dir/native-shots" > "$log_dir/ui-tests.log" 2>&1
rg '^PASS：' "$log_dir/ui-tests.log"
