#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
IMPORTER_FILE="$PROJECT_DIR/Sources/PagecaseApp/SafariOnDemandImporter.swift"

scriptBlock=$(sed -n '/private static let scriptSource = """/,/^  """/p' "$IMPORTER_FILE")
forbiddenScriptPattern='(^|[[:space:]])(close|quit|delete|move|activate)([[:space:]]|$)|make new|do JavaScript|open location|set (URL|name|visible) of'
backgroundPattern='Timer|DispatchSourceTimer|NSWorkspace\.didLaunchApplicationNotification|Task\.detached'

if print -r -- "$scriptBlock" | rg -ni "$forbiddenScriptPattern"; then
  print -u2 "Safari 读取脚本包含修改浏览器状态的语句"
  exit 1
fi

if rg -n "$backgroundPattern" "$IMPORTER_FILE"; then
  print -u2 "Safari 按需读取器包含后台触发路径"
  exit 1
fi

for requiredRead in \
  'tabs of front window' \
  'name of currentTab' \
  'URL of currentTab' \
  'visible of currentTab'; do
  if ! print -r -- "$scriptBlock" | rg -q -F "$requiredRead"; then
    print -u2 "Safari 读取脚本缺少预期的只读字段：$requiredRead"
    exit 1
  fi
done

print "Safari 按需读取静态安全检查通过"
