import assert from "node:assert/strict"
import test from "node:test"

import { CommandExecutionError, executeCommand } from "../commands.js"

test("focusTab 只聚焦目标窗口和标签", async () => {
  const calls = []
  const api = {
    windows: {
      async update(id, changes) {
        calls.push(["window", id, changes])
      }
    },
    tabs: {
      async update(id, changes) {
        calls.push(["tab", id, changes])
      }
    }
  }

  const result = await executeCommand(
    { type: "focusTab", tabId: 10, windowId: 20 },
    api
  )

  assert.equal(result.message, "已定位到 Chrome 标签")
  assert.deepEqual(calls, [
    ["window", 20, { focused: true }],
    ["tab", 10, { active: true }]
  ])
})

test("openUrl 每次只创建一个标签", async () => {
  const calls = []
  const api = {
    tabs: {
      async create(changes) {
        calls.push(changes)
      }
    }
  }

  await executeCommand(
    { type: "openUrl", url: "https://example.com/page" },
    api
  )

  assert.deepEqual(calls, [{ url: "https://example.com/page", active: true }])
})

test("restoreGroup 只分组本次新建的标签并保留顺序", async () => {
  const calls = []
  let nextTabId = 101
  const api = {
    tabs: {
      async create(changes) {
        const id = nextTabId
        nextTabId += 1
        calls.push(["create", id, changes])
        return { id }
      },
      async group(options) {
        calls.push(["group", options])
        return 88
      }
    },
    tabGroups: {
      async update(id, changes) {
        calls.push(["updateGroup", id, changes])
      }
    }
  }

  const result = await executeCommand(
    {
      type: "restoreGroup",
      groupTitle: "开发",
      groupColor: "blue",
      urls: [
        "https://example.com/first",
        "https://example.com/second"
      ]
    },
    api
  )

  assert.deepEqual(result, {
    message: "已恢复「开发」，共 2 个网页",
    createdTabCount: 2,
    groupCreated: true
  })
  assert.deepEqual(calls, [
    [
      "create",
      101,
      { url: "https://example.com/first", active: false }
    ],
    [
      "create",
      102,
      { url: "https://example.com/second", active: false }
    ],
    ["group", { tabIds: [101, 102] }],
    [
      "updateGroup",
      88,
      { title: "开发", color: "blue", collapsed: false }
    ]
  ])
})

test("restoreGroup 创建中断时报告已确认创建的数量", async () => {
  let createCount = 0
  const api = {
    tabs: {
      async create() {
        createCount += 1
        if (createCount === 2) {
          throw new Error("模拟创建失败")
        }
        return { id: 100 + createCount }
      }
    }
  }

  await assert.rejects(
    executeCommand(
      {
        type: "restoreGroup",
        groupTitle: "开发",
        groupColor: "blue",
        urls: [
          "https://example.com/first",
          "https://example.com/second"
        ]
      },
      api
    ),
    error => {
      assert.equal(error instanceof CommandExecutionError, true)
      assert.equal(error.failureStage, "creatingTabs")
      assert.equal(error.createdTabCount, 1)
      assert.equal(error.groupCreated, false)
      return true
    }
  )
})

test("restoreGroup 分组失败时保留全部新标签并报告部分完成", async () => {
  let nextTabId = 201
  const api = {
    tabs: {
      async create() {
        const id = nextTabId
        nextTabId += 1
        return { id }
      },
      async group() {
        throw new Error("模拟分组失败")
      }
    }
  }

  await assert.rejects(
    executeCommand(
      {
        type: "restoreGroup",
        groupTitle: "开发",
        groupColor: "blue",
        urls: [
          "https://example.com/first",
          "https://example.com/second"
        ]
      },
      api
    ),
    error => {
      assert.equal(error.failureStage, "groupingTabs")
      assert.equal(error.createdTabCount, 2)
      assert.equal(error.groupCreated, false)
      return true
    }
  )
})

test("restoreGroup 样式更新失败时说明标签已经成组", async () => {
  let nextTabId = 301
  const api = {
    tabs: {
      async create() {
        const id = nextTabId
        nextTabId += 1
        return { id }
      },
      async group() {
        return 88
      }
    },
    tabGroups: {
      async update() {
        throw new Error("模拟样式更新失败")
      }
    }
  }

  await assert.rejects(
    executeCommand(
      {
        type: "restoreGroup",
        groupTitle: "开发",
        groupColor: "blue",
        urls: ["https://example.com/first"]
      },
      api
    ),
    error => {
      assert.equal(error.failureStage, "updatingGroup")
      assert.equal(error.createdTabCount, 1)
      assert.equal(error.groupCreated, true)
      return true
    }
  )
})

test("未知命令和非 Web 地址会被拒绝", async () => {
  await assert.rejects(
    executeCommand({ type: "unknown" }, {}),
    /未知命令/
  )
  await assert.rejects(
    executeCommand(
      { type: "openUrl", url: "file:///tmp/private" },
      { tabs: { create: async () => {} } }
    ),
    /网址无效/
  )
  await assert.rejects(
    executeCommand(
      {
        type: "restoreGroup",
        groupTitle: "无效",
        groupColor: "blue",
        urls: ["file:///tmp/private"]
      },
      {}
    ),
    /参数不完整/
  )
})
