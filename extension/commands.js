import { isSupportedUrl } from "./snapshot.js"

const SUPPORTED_GROUP_COLORS = new Set([
  "grey",
  "blue",
  "red",
  "yellow",
  "green",
  "pink",
  "purple",
  "cyan",
  "orange"
])

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
  case "restoreGroup": {
    if (
      typeof command.groupTitle !== "string"
      || !SUPPORTED_GROUP_COLORS.has(command.groupColor)
      || !Array.isArray(command.urls)
      || command.urls.length === 0
      || !command.urls.every(isSupportedUrl)
    ) {
      throw new Error("恢复标签组命令参数不完整")
    }

    const createdTabIds = []
    for (const url of command.urls) {
      const tab = await api.tabs.create({ url, active: false })
      if (!Number.isInteger(tab?.id)) {
        throw new Error("Chrome 未返回新标签标识")
      }
      createdTabIds.push(tab.id)
    }

    const groupId = await api.tabs.group({ tabIds: createdTabIds })
    await api.tabGroups.update(groupId, {
      title: command.groupTitle,
      color: command.groupColor,
      collapsed: false
    })
    const displayTitle = command.groupTitle.trim() || "未命名标签组"
    return `已恢复「${displayTitle}」，共 ${createdTabIds.length} 个网页`
  }
  case "pong":
    return "pong"
  default:
    throw new Error("未知命令")
  }
}
