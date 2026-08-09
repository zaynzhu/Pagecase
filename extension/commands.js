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

export class CommandExecutionError extends Error {
  constructor(
    message,
    {
      failureStage,
      createdTabCount = 0,
      groupCreated = false
    } = {}
  ) {
    super(message)
    this.name = "CommandExecutionError"
    this.failureStage = failureStage
    this.createdTabCount = createdTabCount
    this.groupCreated = groupCreated
  }
}

export async function executeCommand(command, api = chrome) {
  switch (command.type) {
  case "focusTab":
    if (!Number.isInteger(command.tabId) || !Number.isInteger(command.windowId)) {
      throw new Error("定位命令参数不完整")
    }
    await api.windows.update(command.windowId, { focused: true })
    await api.tabs.update(command.tabId, { active: true })
    return { message: "已定位到 Chrome 标签" }
  case "openUrl":
    if (!isSupportedUrl(command.url)) {
      throw new Error("打开命令网址无效")
    }
    await api.tabs.create({ url: command.url, active: true })
    return { message: "已在 Chrome 中打开网页", createdTabCount: 1 }
  case "restoreGroup": {
    if (
      typeof command.groupTitle !== "string"
      || !SUPPORTED_GROUP_COLORS.has(command.groupColor)
      || !Array.isArray(command.urls)
      || command.urls.length === 0
      || !command.urls.every(isSupportedUrl)
    ) {
      throw new CommandExecutionError("恢复标签组命令参数不完整", {
        failureStage: "validation"
      })
    }

    const createdTabIds = []
    for (const [index, url] of command.urls.entries()) {
      let tab
      try {
        tab = await api.tabs.create({ url, active: false })
      } catch {
        throw new CommandExecutionError(
          `Chrome 创建第 ${index + 1} 个标签时失败`,
          {
            failureStage: "creatingTabs",
            createdTabCount: createdTabIds.length
          }
        )
      }
      if (!Number.isInteger(tab?.id)) {
        throw new CommandExecutionError("Chrome 未返回新标签标识", {
          failureStage: "creatingTabs",
          createdTabCount: createdTabIds.length + 1
        })
      }
      createdTabIds.push(tab.id)
    }

    let groupId
    try {
      groupId = await api.tabs.group({ tabIds: createdTabIds })
    } catch {
      throw new CommandExecutionError("Chrome 未能把新标签组成标签组", {
        failureStage: "groupingTabs",
        createdTabCount: createdTabIds.length
      })
    }
    try {
      await api.tabGroups.update(groupId, {
        title: command.groupTitle,
        color: command.groupColor,
        collapsed: false
      })
    } catch {
      throw new CommandExecutionError("标签组已创建，但组名或颜色设置失败", {
        failureStage: "updatingGroup",
        createdTabCount: createdTabIds.length,
        groupCreated: true
      })
    }
    const displayTitle = command.groupTitle.trim() || "未命名标签组"
    return {
      message: `已恢复「${displayTitle}」，共 ${createdTabIds.length} 个网页`,
      createdTabCount: createdTabIds.length,
      groupCreated: true
    }
  }
  case "pong":
    return { message: "pong" }
  default:
    throw new Error("未知命令")
  }
}
