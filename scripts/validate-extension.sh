#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
RUNTIME_FILES=(
  "$PROJECT_DIR/extension/background.js"
  "$PROJECT_DIR/extension/commands.js"
  "$PROJECT_DIR/extension/snapshot.js"
)

forbiddenPattern='(chrome|api)\.tabs\.(remove|move|discard|ungroup)|(chrome|api)\.windows\.remove'
groupWritePattern='(chrome|api)\.tabs\.group|(chrome|api)\.tabGroups\.update'
networkPattern='fetch[[:space:]]*\(|XMLHttpRequest|WebSocket|EventSource'

if rg -n "$forbiddenPattern" "${RUNTIME_FILES[@]}"; then
  print -u2 "发现禁止的 Chrome 写 API"
  exit 1
fi

if rg -n "$groupWritePattern" \
  "$PROJECT_DIR/extension/background.js" \
  "$PROJECT_DIR/extension/snapshot.js"; then
  print -u2 "标签组写 API 只能存在于整组恢复命令"
  exit 1
fi

groupCallCount=$(rg -o 'api\.tabs\.group[[:space:]]*\(' \
  "$PROJECT_DIR/extension/commands.js" | wc -l | tr -d ' ')
groupUpdateCount=$(rg -o 'api\.tabGroups\.update[[:space:]]*\(' \
  "$PROJECT_DIR/extension/commands.js" | wc -l | tr -d ' ')
if [[ "$groupCallCount" != "1" || "$groupUpdateCount" != "1" ]]; then
  print -u2 "整组恢复命令中的标签组写 API 数量异常"
  exit 1
fi

if ! rg -q 'api\.tabs\.group\(\{ tabIds: createdTabIds \}\)' \
  "$PROJECT_DIR/extension/commands.js"; then
  print -u2 "整组恢复没有严格使用本次新建的标签标识"
  exit 1
fi

if rg -n "$networkPattern" "${RUNTIME_FILES[@]}"; then
  print -u2 "发现外部网络调用"
  exit 1
fi

print "扩展静态安全检查通过"
