import assert from "node:assert/strict"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { spawn } from "node:child_process"

const projectDir = path.resolve(import.meta.dirname, "..")
const bridgePath = path.join(projectDir, ".build", "release", "PagecaseBridge")
const dataRoot = await mkdtemp(path.join(os.tmpdir(), "pagecase-bridge-"))
const sourceId = "bridge-check"

try {
  const child = spawn(bridgePath, [], {
    env: {
      ...process.env,
      PAGECASE_DATA_ROOT: dataRoot
    },
    stdio: ["pipe", "pipe", "pipe"]
  })

  const output = []
  const errors = []
  child.stdout.on("data", chunk => output.push(chunk))
  child.stderr.on("data", chunk => errors.push(chunk))

  child.stdin.write(frame({
    type: "snapshot",
    payload: {
      schemaVersion: 1,
      source: {
        id: sourceId,
        kind: "chrome",
        label: "Chrome · Bridge 检查",
        capturedAt: "2026-08-06T12:00:00Z"
      },
      windows: []
    }
  }))
  child.stdin.write(frame({
    type: "commandResult",
    commandId: "restore-result-check",
    sourceId,
    success: false,
    message: "Chrome 未能把新标签组成标签组",
    action: "restoreGroup",
    createdTabCount: 2,
    groupCreated: false,
    failureStage: "groupingTabs"
  }))
  child.stdin.write(frame({ type: "ping" }))
  child.stdin.end()

  const exitCode = await waitForExit(child, 3000)
  assert.equal(exitCode, 0, Buffer.concat(errors).toString("utf8"))

  const messages = decodeFrames(Buffer.concat(output))
  assert.equal(messages.some(message => message.type === "pong"), true)

  const liveFile = path.join(dataRoot, "live", `${sourceId}.json`)
  const saved = JSON.parse(await readFile(liveFile, "utf8"))
  assert.equal(saved.source.id, sourceId)
  assert.equal(saved.source.label, "Chrome · Bridge 检查")

  const resultFile = path.join(dataRoot, "results", "restore-result-check.json")
  const result = JSON.parse(await readFile(resultFile, "utf8"))
  assert.equal(result.action, "restoreGroup")
  assert.equal(result.createdTabCount, 2)
  assert.equal(result.groupCreated, false)
  assert.equal(result.failureStage, "groupingTabs")

  console.log("PagecaseBridge: 快照、结构化结果与 ping 往返检查通过")
} finally {
  await rm(dataRoot, { recursive: true, force: true })
}

function frame(value) {
  const payload = Buffer.from(JSON.stringify(value), "utf8")
  const length = Buffer.alloc(4)
  length.writeUInt32LE(payload.length)
  return Buffer.concat([length, payload])
}

function decodeFrames(data) {
  const messages = []
  let offset = 0

  while (offset < data.length) {
    assert.ok(data.length - offset >= 4, "消息长度前缀不完整")
    const length = data.readUInt32LE(offset)
    offset += 4
    assert.ok(data.length - offset >= length, "消息正文不完整")
    messages.push(JSON.parse(data.subarray(offset, offset + length).toString("utf8")))
    offset += length
  }

  return messages
}

function waitForExit(child, timeout) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill()
      reject(new Error("Bridge 检查超时"))
    }, timeout)

    child.once("error", error => {
      clearTimeout(timer)
      reject(error)
    })
    child.once("exit", code => {
      clearTimeout(timer)
      resolve(code)
    })
  })
}
