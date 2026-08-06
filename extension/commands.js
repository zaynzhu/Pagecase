import { isSupportedUrl } from "./snapshot.js"

export async function executeCommand(command, api = chrome) {
  switch (command.type) {
  case "focusTab":
    if (!Number.isInteger(command.tabId) || !Number.isInteger(command.windowId)) {
      throw new Error("定位命令参数不完整")
    }
    await api.windows.update(command.windowId, { focused: true })
    await api.tabs.update(command.tabId, { active: true })
    return "已定位到 Chrome 标签"
  case "openUrl":
    if (!isSupportedUrl(command.url)) {
      throw new Error("打开命令网址无效")
    }
    await api.tabs.create({ url: command.url, active: true })
    return "已在 Chrome 中打开网页"
  case "pong":
    return "pong"
  default:
    throw new Error("未知命令")
  }
}
