export const SCHEMA_VERSION = 1
export const UNGROUPED_ID = -1

export function isSupportedUrl(value) {
  try {
    const url = new URL(value)
    return url.protocol === "http:" || url.protocol === "https:"
  } catch {
    return false
  }
}

export function buildLiveState({
  windows,
  groups,
  sourceId,
  sourceLabel = "Chrome",
  capturedAt = new Date()
}) {
  const groupMap = new Map(groups.map(group => [group.id, group]))
  const normalWindows = windows.filter(window => window.type === "normal" && !window.incognito)

  return {
    schemaVersion: SCHEMA_VERSION,
    source: {
      id: sourceId,
      kind: "chrome",
      label: sourceLabel,
      capturedAt: isoDate(capturedAt)
    },
    windows: normalWindows.map((window, windowOrder) => {
      const tabs = (window.tabs ?? [])
        .filter(tab => !tab.incognito && isSupportedUrl(tab.url))
        .sort((left, right) => left.index - right.index)

      const groupedTabs = new Map()
      const ungroupedTabs = []

      for (const tab of tabs) {
        const page = pageFromTab(tab)
        if (tab.groupId === UNGROUPED_ID || !groupMap.has(tab.groupId)) {
          ungroupedTabs.push(page)
          continue
        }
        const current = groupedTabs.get(tab.groupId) ?? []
        current.push(page)
        groupedTabs.set(tab.groupId, current)
      }

      const windowGroups = [...groupedTabs.entries()]
        .map(([groupId, groupTabs]) => {
          const group = groupMap.get(groupId)
          return {
            id: groupId,
            title: group.title ?? "",
            color: normalizeGroupColor(group.color),
            collapsed: Boolean(group.collapsed),
            order: Math.min(...groupTabs.map(tab => tab.index)),
            tabs: groupTabs
          }
        })
        .sort((left, right) => left.order - right.order)
        .map((group, order) => ({ ...group, order }))

      return {
        id: window.id,
        order: windowOrder,
        focused: Boolean(window.focused),
        groups: windowGroups,
        ungroupedTabs
      }
    })
  }
}

export function createDebouncer(callback, delay, timers = globalThis) {
  let timerId

  return (...args) => {
    if (timerId !== undefined) {
      timers.clearTimeout(timerId)
    }
    timerId = timers.setTimeout(() => {
      timerId = undefined
      callback(...args)
    }, delay)
  }
}

function pageFromTab(tab) {
  return {
    id: tab.id,
    windowId: tab.windowId,
    groupId: tab.groupId === UNGROUPED_ID ? null : tab.groupId,
    index: tab.index,
    title: tab.title ?? "",
    url: tab.url,
    pinned: Boolean(tab.pinned),
    active: Boolean(tab.active),
    audible: Boolean(tab.audible),
    discarded: Boolean(tab.discarded)
  }
}

function normalizeGroupColor(value) {
  const allowed = new Set([
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
  return allowed.has(value) ? value : "grey"
}

function isoDate(value) {
  const date = value instanceof Date ? value : new Date(value)
  return date.toISOString().replace(/\.\d{3}Z$/, "Z")
}
