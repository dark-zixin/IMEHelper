#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
log_dir="$repo_root/tmp/topics/11070549_focus_rew/log"
mkdir -p "$log_dir"

python3 - "$repo_root/IMEHelper/AppDelegate.swift" "$log_dir/AppDelegate-under-test.swift" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
marker = "@main\n"
if source.count(marker) != 1:
    raise SystemExit("AppDelegate 的 @main 數量不是一處，停止測試")
Path(sys.argv[2]).write_text(source.replace(marker, "", 1))
PY

source_files=("$repo_root"/IMEHelper/*.swift)
source_files=("${(@)source_files:#*/AppDelegate.swift}")
source_files=("${(@)source_files:#*/TextInjector.swift}")
source_files=("${(@)source_files:#*/PanelManagerWindowController.swift}")

swiftc -swift-version 5 -default-isolation MainActor \
  -module-cache-path "$log_dir/swift-module-cache" \
  "$log_dir/AppDelegate-under-test.swift" \
  "${source_files[@]}" \
  "$repo_root/Tests/FocusHandoff/AppDelegateRunner.swift" \
  -o "$log_dir/focus-appdelegate-tests"

if ! "$log_dir/focus-appdelegate-tests" > "$log_dir/appdelegate-tests.log" 2>&1; then
  cat "$log_dir/appdelegate-tests.log"
  exit 1
fi

cat "$log_dir/appdelegate-tests.log"
