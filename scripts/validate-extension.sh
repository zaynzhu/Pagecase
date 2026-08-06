#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
RUNTIME_FILES=(
  "$PROJECT_DIR/extension/background.js"
  "$PROJECT_DIR/extension/commands.js"
  "$PROJECT_DIR/extension/snapshot.js"
)

forbiddenPattern='chrome\.tabs\.(remove|move|discard|group|ungroup)|chrome\.windows\.remove|chrome\.tabGroups\.update'
networkPattern='fetch[[:space:]]*\(|XMLHttpRequest|WebSocket|EventSource'

if rg -n "$forbiddenPattern" "${RUNTIME_FILES[@]}"; then
  print -u2 "发现禁止的 Chrome 写 API"
  exit 1
fi

if rg -n "$networkPattern" "${RUNTIME_FILES[@]}"; then
  print -u2 "发现外部网络调用"
  exit 1
fi

print "扩展静态安全检查通过"
