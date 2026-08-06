#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
HOST_NAME="com.zaynzhu.pagecase"
EXTENSION_ID=${1:-}
APP_PATH=${2:-"$PROJECT_DIR/dist/页匣.app"}
MANIFEST_DIR=${3:-"$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"}
APP_PATH=${APP_PATH:A}
MANIFEST_DIR=${MANIFEST_DIR:A}
BRIDGE_PATH="$APP_PATH/Contents/MacOS/PagecaseBridge"
MANIFEST_PATH="$MANIFEST_DIR/$HOST_NAME.json"

if [[ ! "$EXTENSION_ID" =~ '^[a-p]{32}$' ]]; then
  print -u2 "扩展标识必须是 32 位 a-p 字符"
  exit 1
fi

if [[ ! -x "$BRIDGE_PATH" ]]; then
  print -u2 "未找到 Bridge：$BRIDGE_PATH"
  exit 1
fi

mkdir -p "$MANIFEST_DIR"
TEMP_FILE=$(mktemp "$MANIFEST_DIR/.pagecase-host.XXXXXX")
trap 'rm -f "$TEMP_FILE"' EXIT

printf '%s\n' \
  '{' \
  "  \"name\": \"$HOST_NAME\"," \
  '  "description": "页匣 Native Messaging Bridge",' \
  "  \"path\": \"$BRIDGE_PATH\"," \
  '  "type": "stdio",' \
  '  "allowed_origins": [' \
  "    \"chrome-extension://$EXTENSION_ID/\"" \
  '  ]' \
  '}' > "$TEMP_FILE"

chmod 644 "$TEMP_FILE"
mv "$TEMP_FILE" "$MANIFEST_PATH"
trap - EXIT

print "已安装 Native Messaging Host：$MANIFEST_PATH"
