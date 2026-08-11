import { CommandExecutionError, executeCommand } from "./commands.js"
import { buildLiveState, createDebouncer } from "./snapshot.js"

const HOST_NAME = "com.zaynzhu.pagecase"
const CAPTURE_DELAY = 400
const HEARTBEAT_INTERVAL = 20_000

let nativePort
let sourceId
let reconnectDelay = 500

async function ensureSourceId() {
  const stored = await chrome.storage.local.get("sourceId")
  if (stored.sourceId) {
    return stored.sourceId
  }

  const created = crypto.randomUUID()
  await chrome.storage.local.set({ sourceId: created })
  return created
}

async function capture() {
  if (!nativePort || !sourceId) {
    return
  }

  const [windows, groups] = await Promise.all([
    chrome.windows.getAll({ populate: true, windowTypes: ["normal"] }),
    chrome.tabGroups.query({})
  ])
  const payload = buildLiveState({
    windows,
    groups,
    sourceId,
    capturedAt: new Date()
  })
  nativePort.postMessage({ type: "snapshot", payload })
}

const scheduleCapture = createDebouncer(() => {
  capture().catch(reportRuntimeError)
}, CAPTURE_DELAY)

async function handleNativeMessage(command) {
  if (command.type === "pong") {
    return
  }

  try {
    const result = await executeCommand(command)
    nativePort?.postMessage({
      type: "commandResult",
      commandId: command.commandId,
      sourceId,
      success: true,
      action: command.type,
      ...result
    })
    scheduleCapture()
  } catch (error) {
    const details = error instanceof CommandExecutionError
      ? {
          failureStage: error.failureStage,
          createdTabCount: error.createdTabCount,
          groupCreated: error.groupCreated,
          restoredGroupId: error.restoredGroupId
        }
      : {}
    nativePort?.postMessage({
      type: "commandResult",
      commandId: command.commandId,
      sourceId,
      success: false,
      message: error instanceof Error ? error.message : "命令执行失败",
      action: command.type,
      ...details
    })
  }
}

async function connect() {
  sourceId = await ensureSourceId()
  nativePort = chrome.runtime.connectNative(HOST_NAME)

  nativePort.onMessage.addListener(message => {
    handleNativeMessage(message).catch(reportRuntimeError)
  })
  nativePort.onDisconnect.addListener(() => {
    nativePort = undefined
    const lastError = chrome.runtime.lastError
    if (lastError) {
      console.info(`页匣连接已断开：${lastError.message}`)
    }
    setTimeout(() => {
      connect().catch(reportRuntimeError)
    }, reconnectDelay)
    reconnectDelay = Math.min(reconnectDelay * 2, 5000)
  })

  reconnectDelay = 500
  await capture()
}

function reportRuntimeError(error) {
  const message = error instanceof Error ? error.message : String(error)
  console.error(`页匣连接器：${message}`)
}

const tabEvents = [
  chrome.tabs.onCreated,
  chrome.tabs.onUpdated,
  chrome.tabs.onMoved,
  chrome.tabs.onAttached,
  chrome.tabs.onDetached,
  chrome.tabs.onRemoved,
  chrome.tabs.onActivated
]
const windowEvents = [
  chrome.windows.onCreated,
  chrome.windows.onRemoved,
  chrome.windows.onFocusChanged
]
const groupEvents = [
  chrome.tabGroups.onCreated,
  chrome.tabGroups.onUpdated,
  chrome.tabGroups.onMoved,
  chrome.tabGroups.onRemoved
]

for (const event of [...tabEvents, ...windowEvents, ...groupEvents]) {
  event.addListener(scheduleCapture)
}

connect().catch(reportRuntimeError)
setInterval(() => {
  capture().catch(reportRuntimeError)
}, HEARTBEAT_INTERVAL)
