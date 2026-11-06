#!/bin/zsh
set -euo pipefail

repo_root=${0:A:h:h}
if ! command -v rg >/dev/null 2>&1; then
  print -u2 '缺少 rg，無法執行診斷斷言'
  exit 2
fi
topic_dir="$repo_root/tmp/topics/11062140_cangjie_lookup"
log_dir="$topic_dir/log"
mkdir -p "$log_dir"

binary="$log_dir/cangjie-model-tests"
export CANGJIE_TEST_ROOT="$log_dir"
swiftc -swift-version 5 -module-cache-path "$log_dir/swift-module-cache" \
  "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
  "$repo_root/IMEHelper/CangjieDictionary.swift" \
  "$repo_root/IMEHelper/CangjieSavedListStore.swift" \
  "$repo_root/Tests/CangjieModels/Runner.swift" \
  -o "$binary"

if [[ $# -gt 1 ]]; then
  print -u2 '用法：scripts/test-cangjie-models.sh [IMEHelper.app 路徑]'
  exit 2
fi

if [[ $# -eq 1 ]]; then
  "$binary" "$repo_root/IMEHelper/cangjie5.tsv" "$1" > "$log_dir/cangjie-model-tests.log" 2>&1
else
  "$binary" "$repo_root/IMEHelper/cangjie5.tsv" > "$log_dir/cangjie-model-tests.log" 2>&1
fi

if ! rg -q '^PASS：倉頡模型測試全部通過$' "$log_dir/cangjie-model-tests.log"; then
  print -u2 '模型測試未回報全部通過'
  exit 1
fi
if ! rg -q 'operation=dictionaryLoad result=success .*entryCount=79262 characterCount=75151 ' "$log_dir/cangjie-model-tests.log"; then
  print -u2 '真碼表筆數或原字數不符'
  exit 1
fi

for marker in 'reason=emptyNotCreated' 'reason=resourceMissing' 'reason=resourceReadFailed' 'reason=resourceMalformed' 'reason=storeMalformed' 'reason=storeDuplicateIdentifier' 'reason=storeDuplicateCharacter' 'reason=storeInvalidCharacter' 'reason=storeInvalidCode' 'reason=storeLegacyTextMismatch' 'reason=unsupportedVersion' 'reason=storeReadFailed' 'reason=writeFailed' 'operation=listSave result=success' 'operation=listRemove result=success'; do
  if ! rg -q "$marker" "$log_dir/cangjie-model-tests.log"; then
    print -u2 "缺少診斷分支：$marker"
    exit 1
  fi
done

if rg -q '敏感原文|偽造欄位|原檔內容|壞日期|errorDescription|localizedDescription|userInfo' "$log_dir/cangjie-model-tests.log"; then
  print -u2 '診斷輸出含原文或錯誤內文'
  exit 1
fi
python3 - "$log_dir/cangjie-model-tests.log" <<'PY'
from pathlib import Path
import re
import sys
lines = [line for line in Path(sys.argv[1]).read_text().splitlines() if '[CangjieLookup]' in line]
shape = re.compile(r'\[CangjieLookup\] operation=[A-Za-z]+ result=[A-Za-z]+ reason=[A-Za-z]+ recordID=(?:none|[0-9A-F-]{36}) entryCount=\d+ characterCount=\d+ errorDomain=(?:NSCocoaErrorDomain|NSPOSIXErrorDomain|unknown) errorCode=-?\d+$')
if not lines or any(not shape.search(line) for line in lines):
    raise SystemExit('診斷欄位形狀或錯誤 domain 不符')
expected_reasons = [
    'storeDuplicateIdentifier',
    'storeDuplicateIdentifier',
    'storeDuplicateCharacter',
    'storeDuplicateCharacter',
    'storeInvalidCharacter',
    'storeInvalidCharacter',
    'storeInvalidCode',
    'storeMalformed',
    'none',
    'storeDuplicateIdentifier',
    'storeDuplicateIdentifier',
    'storeInvalidCharacter',
    'storeInvalidCode',
    'storeLegacyTextMismatch',
    'none',
]
actual_reasons = [re.search(r' reason=([A-Za-z]+) ', line).group(1) for line in lines[-len(expected_reasons):]]
if actual_reasons != expected_reasons:
    raise SystemExit('真 JSON 診斷原因與固定對照不符')
PY

print 'PASS：模型測試與診斷遮蔽'

python3 - "$repo_root/IMEHelper/CangjieDictionary.swift" "$log_dir/CangjieDictionary-mutant.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
old = 'codes.filter { !$0.hasPrefix("x") } + codes.filter { $0.hasPrefix("x") }'
new = 'codes.filter { $0.hasPrefix("x") } + codes.filter { !$0.hasPrefix("x") }'
if source.count(old) != 1:
    raise SystemExit('排序突變點已變更')
Path(sys.argv[2]).write_text(source.replace(old, new))
PY
swiftc -swift-version 5 -module-cache-path "$log_dir/swift-module-cache" \
  "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
  "$log_dir/CangjieDictionary-mutant.swift" \
  "$repo_root/IMEHelper/CangjieSavedListStore.swift" \
  "$repo_root/Tests/CangjieModels/Runner.swift" \
  -o "$log_dir/cangjie-sort-mutant-tests"
if "$log_dir/cangjie-sort-mutant-tests" "$repo_root/IMEHelper/cangjie5.tsv" > "$log_dir/cangjie-sort-mutant.log" 2>&1; then
  print -u2 '排序突變未被測試攔下'
  exit 1
fi
if ! rg -q '^FAIL：真碼表固定字碼與排序$' "$log_dir/cangjie-sort-mutant.log"; then
  print -u2 '排序突變未由固定字碼斷言攔下'
  exit 1
fi

python3 - "$repo_root/IMEHelper/CangjieSavedListStore.swift" "$log_dir/CangjieSavedListStore-mutant.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
old = 'try data.write(to: fileURL, options: .atomic)'
if source.count(old) != 1:
    raise SystemExit('原子寫入突變點已變更')
Path(sys.argv[2]).write_text(source.replace(old, '_ = data'))
PY
swiftc -swift-version 5 -module-cache-path "$log_dir/swift-module-cache" \
  "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
  "$repo_root/IMEHelper/CangjieDictionary.swift" \
  "$log_dir/CangjieSavedListStore-mutant.swift" \
  "$repo_root/Tests/CangjieModels/Runner.swift" \
  -o "$log_dir/cangjie-write-mutant-tests"
if "$log_dir/cangjie-write-mutant-tests" "$repo_root/IMEHelper/cangjie5.tsv" > "$log_dir/cangjie-write-mutant.log" 2>&1; then
  print -u2 '持久化突變未被測試攔下'
  exit 1
fi
if ! rg -q '^FAIL：存後全新實例重讀順序$' "$log_dir/cangjie-write-mutant.log"; then
  print -u2 '持久化突變未由重讀斷言攔下'
  exit 1
fi

print 'PASS：排序與持久化突變均被斷言攔下'

python3 - "$repo_root/IMEHelper/CangjieSavedListStore.swift" "$log_dir/CangjieSavedListStore-resave-mutant.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
old = 'let proposed = [entry] + entries.filter { Self.rawKey($0.character) != key }'
new = 'let proposed = [entry] + entries'
if source.count(old) != 1:
    raise SystemExit('重存去重突變點已變更')
Path(sys.argv[2]).write_text(source.replace(old, new))
PY
swiftc -swift-version 5 -module-cache-path "$log_dir/swift-module-cache" \
  "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
  "$repo_root/IMEHelper/CangjieDictionary.swift" \
  "$log_dir/CangjieSavedListStore-resave-mutant.swift" \
  "$repo_root/Tests/CangjieModels/Runner.swift" \
  -o "$log_dir/cangjie-resave-mutant-tests"
if "$log_dir/cangjie-resave-mutant-tests" "$repo_root/IMEHelper/cangjie5.tsv" > "$log_dir/cangjie-resave-mutant.log" 2>&1; then
  print -u2 '重存去重突變未被測試攔下'
  exit 1
fi
if ! rg -q '^FAIL：重存同字排前且不重複$' "$log_dir/cangjie-resave-mutant.log"; then
  print -u2 '重存去重突變未由指定斷言攔下'
  exit 1
fi

python3 - "$repo_root/IMEHelper/CangjieSavedListStore.swift" "$log_dir/CangjieSavedListStore-legacy-mutant.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
old = 'if version == 1 {'
if source.count(old) != 1:
    raise SystemExit('v1 相容分支突變點已變更')
Path(sys.argv[2]).write_text(source.replace(old, 'if false {'))
PY
swiftc -swift-version 5 -module-cache-path "$log_dir/swift-module-cache" \
  "$repo_root/IMEHelper/CangjieDiagnostics.swift" \
  "$repo_root/IMEHelper/CangjieDictionary.swift" \
  "$log_dir/CangjieSavedListStore-legacy-mutant.swift" \
  "$repo_root/Tests/CangjieModels/Runner.swift" \
  -o "$log_dir/cangjie-legacy-mutant-tests"
if "$log_dir/cangjie-legacy-mutant-tests" "$repo_root/IMEHelper/cangjie5.tsv" > "$log_dir/cangjie-legacy-mutant.log" 2>&1; then
  print -u2 'v1 相容分支突變未被測試攔下'
  exit 1
fi
if ! rg -q '^FAIL：v1 字面 JSON 轉換載入$' "$log_dir/cangjie-legacy-mutant.log"; then
  print -u2 'v1 相容分支突變未由字面 fixture 斷言攔下'
  exit 1
fi

print 'PASS：重存去重與 v1 相容突變均被斷言攔下'
