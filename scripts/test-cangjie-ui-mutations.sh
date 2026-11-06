#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
if ! command -v rg >/dev/null 2>&1; then
  print -u2 '缺少 rg，無法確認 UI 突變結果'
  exit 2
fi
log_dir="$repo_root/tmp/topics/11062140_cangjie_lookup/compact-v2/log"
app_path=${1:-"$repo_root/build/cangjie-derived/Build/Products/Debug/IMEHelper.app"}
mkdir -p "$log_dir/ui-mutations"

# 只改測試副本，確認斷言能攔下實際操作入口與版面的退化。
python3 - "$repo_root/IMEHelper" "$log_dir/ui-mutations" <<'PY'
from pathlib import Path
import sys

source_dir, output_dir = map(Path, sys.argv[1:])
changes = {
    "save": ("CangjieLookupContentView.swift", "self?.saveCharacter(result)", "_ = self"),
    "composition": ("CangjieLookupContentView.swift",
                    "guard let store, dictionary != nil, !input.isComposing, pendingDeleteID == nil else",
                    "guard let store, dictionary != nil, pendingDeleteID == nil else"),
    "viewport": ("CangjieLookupContentView.swift",
                 "otherScroll.frame = NSRect(x: 10, y: headerY + 153, width: innerWidth, height: 60)",
                 "otherScroll.frame = NSRect(x: 10, y: headerY + 153, width: innerWidth, height: 90)"),
    "paste": ("CangjieLookupTextView.swift", "case 9 where isEditable: paste(nil)",
              "case 9 where isEditable: return false"),
    "freeze": ("CangjieLookupContentView.swift", "guard !input.isComposing else {",
               "if input.isComposing && false {"),
    "unknown": ("CangjieLookupContentView.swift",
                'let savedSummary = store == nil ? localize("lookup.saved_unavailable") : "\\(localize("lookup.saved"))  \\(entries.count)"',
                'let savedSummary = "\\(localize("lookup.saved"))  \\(entries.count)"'),
    "savedWidth": ("CangjieLookupContentView.swift",
                   '''actionWidth = ceil(([actionTitle] + alternateActionTitles).reduce(CGFloat(32)) { width, title in
                actionButton.title = title
                return max(width, actionButton.cell?.cellSize.width ?? 0)
            })''',
                   'actionWidth = 32'),
    "anchor": ("CangjieLookupWindowController.swift",
               "lastProgrammaticFrame = window.frame",
               "lastProgrammaticFrame = window.frame\n        manualTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)"),
    "manage": ("CangjieLookupContentView.swift",
               "manage.isEnabled = enabled && store != nil",
               "manage.isEnabled = enabled"),
}
for name, (file, original, replacement) in changes.items():
    source = (source_dir / file).read_text()
    if source.count(original) != 1:
        raise SystemExit(f"{name} 突變點已變更")
    folder = output_dir / name
    folder.mkdir(exist_ok=True)
    (folder / file).write_text(source.replace(original, replacement))
PY

for mutation in save composition viewport paste freeze unknown savedWidth anchor manage; do
  mutation_dir="$log_dir/ui-mutations/$mutation"
  content_source="$repo_root/IMEHelper/CangjieLookupContentView.swift"
  text_source="$repo_root/IMEHelper/CangjieLookupTextView.swift"
  window_source="$repo_root/IMEHelper/CangjieLookupWindowController.swift"
  if [[ $mutation == paste ]]; then
    text_source="$mutation_dir/CangjieLookupTextView.swift"
  elif [[ $mutation == anchor ]]; then
    window_source="$mutation_dir/CangjieLookupWindowController.swift"
  else
    content_source="$mutation_dir/CangjieLookupContentView.swift"
  fi
  swiftc -swift-version 5 -default-isolation MainActor -module-cache-path "$log_dir/swift-module-cache" \
    "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
    "$repo_root/IMEHelper/CangjieDictionary.swift" \
    "$repo_root/IMEHelper/CangjieSavedListStore.swift" \
    "$text_source" "$content_source" \
    "$window_source" \
    "$repo_root/Tests/CangjieUI/Runner.swift" \
    -o "$mutation_dir/runner"
  if "$mutation_dir/runner" "$repo_root" "$app_path" "$mutation_dir/shots" > "$mutation_dir/result.log" 2>&1; then
    print -u2 "$mutation 突變未被測試攔下"
    exit 1
  fi
  case $mutation in
    save) expected='FAIL：逐字存按鈕接上真儲存入口' ;;
    composition) expected='FAIL：組字保存guard不可繞過' ;;
    viewport) expected='FAIL：其他區固定兩列且其餘可捲動' ;;
    paste) expected='FAIL：專用文字元件必須接住CmdV' ;;
    freeze) expected='FAIL：空框組字不得建結果列' ;;
    unknown) expected='FAIL：未知清單不得顯示零筆' ;;
    savedWidth) expected='FAIL：保存成功按鈕 cell 不可裁切' ;;
    anchor) expected='FAIL：夾回不得覆寫手動錨點' ;;
    manage) expected='FAIL：讀取失敗關窗清理後管理仍停用' ;;
  esac
  if ! rg -q -F -x "$expected" "$mutation_dir/result.log"; then
    print -u2 "$mutation 突變未由指定斷言攔下"
    exit 1
  fi
  print "PASS：$mutation 突變被指定斷言攔下"
done
