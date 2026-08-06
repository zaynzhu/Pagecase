#!/bin/zsh
set -euo pipefail

HOST_NAME="com.zaynzhu.pagecase"
MANIFEST_DIR=${1:-"$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"}
MANIFEST_PATH="$MANIFEST_DIR/$HOST_NAME.json"

if [[ -f "$MANIFEST_PATH" ]]; then
  rm "$MANIFEST_PATH"
  print "已删除 Native Messaging Host：$MANIFEST_PATH"
else
  print "没有找到 Native Messaging Host：$MANIFEST_PATH"
fi
