#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
if ! command -v rg >/dev/null 2>&1; then
  print -u2 '缺少 rg，無法確認查碼焦點測試結果'
  exit 2
fi
app_path=${1:-"$repo_root/build/focus-handoff-v2/Build/Products/Debug/IMEHelper.app"}
log_dir="$repo_root/tmp/topics/11070549_focus_rew/log"
probe_app="$log_dir/FocusLookupTests.app"
mkdir -p "$probe_app/Contents/MacOS"
cat > "$probe_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FocusLookupTests</string>
<key>CFBundleIdentifier</key><string>com.dark.IMEHelper.focus-lookup-tests</string>
<key>CFBundleName</key><string>FocusLookupTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swiftc -swift-version 5 -default-isolation MainActor -module-cache-path "$log_dir/swift-module-cache" \
  "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
  "$repo_root/IMEHelper/CangjieDictionary.swift" \
  "$repo_root/IMEHelper/CangjieSavedListStore.swift" \
  "$repo_root/IMEHelper/CangjieLookupTextView.swift" \
  "$repo_root/IMEHelper/CangjieLookupContentView.swift" \
  "$repo_root/IMEHelper/CangjieLookupWindowController.swift" \
  "$repo_root/Tests/FocusHandoff/LookupRunner.swift" \
  -o "$probe_app/Contents/MacOS/FocusLookupTests"

cover_app="$log_dir/FocusLookupCover.app"
mkdir -p "$cover_app/Contents/MacOS"
cp "$probe_app/Contents/MacOS/FocusLookupTests" "$cover_app/Contents/MacOS/FocusLookupTests"
sed 's/com.dark.IMEHelper.focus-lookup-tests/com.dark.IMEHelper.focus-lookup-cover/' "$probe_app/Contents/Info.plist" > "$cover_app/Contents/Info.plist"

# 這項測試會短暫顯示獨立視窗；合成按鍵僅留在測試程序。
result_file="$log_dir/focus-lookup-$(uuidgen).txt"
open -n -W --stderr "$log_dir/focus-lookup-stderr.txt" "$probe_app" --args "$app_path" "$result_file" "$cover_app"
cat "$result_file"
rg -q '^PASS：查碼窗前景操作與被動焦點交接全部通過$' "$result_file"
