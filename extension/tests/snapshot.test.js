import assert from "node:assert/strict"
import test from "node:test"

import { buildLiveState, createDebouncer, isSupportedUrl } from "../snapshot.js"

test("只捕获普通窗口和 Web 页面，并保留重复网址", () => {
  const duplicateUrl = "https://example.com/shared"
  const state = buildLiveState({
    sourceId: "source",
    capturedAt: new Date("2026-08-06T12:00:00Z"),
    groups: [
      { id: 10, title: "开发", color: "blue", collapsed: false },
      { id: 11, title: "", color: "yellow", collapsed: true }
    ],
    windows: [
      {
        id: 1,
        type: "normal",
        incognito: false,
        focused: true,
        tabs: [
          tab(101, 1, 10, 0, "项目", "https://github.com/zaynzhu/Pagecase"),
          tab(102, 1, 10, 1, "重复一", duplicateUrl),
          tab(103, 1, 11, 2, "重复二", duplicateUrl),
          tab(104, 1, -1, 3, "本地文件", "file:///tmp/private"),
          tab(105, 1, -1, 4, "浏览器设置", "chrome://settings"),
          tab(106, 1, -1, 5, "未分组", "https://example.com/free")
        ]
      },
      {
        id: 2,
        type: "normal",
        incognito: true,
        focused: false,
        tabs: [tab(201, 2, -1, 0, "无痕", "https://example.com/private")]
      },
      {
        id: 3,
        type: "popup",
        incognito: false,
        focused: false,
        tabs: [tab(301, 3, -1, 0, "弹窗", "https://example.com/popup")]
      }
    ]
  })

  assert.equal(state.source.capturedAt, "2026-08-06T12:00:00Z")
  assert.equal(state.windows.length, 1)
  assert.equal(state.windows[0].groups.length, 2)
  assert.equal(state.windows[0].groups[0].title, "开发")
  assert.equal(state.windows[0].groups[1].title, "")
  assert.equal(state.windows[0].groups[1].collapsed, true)
  assert.equal(state.windows[0].ungroupedTabs.length, 1)

  const urls = state.windows[0].groups.flatMap(group => group.tabs.map(page => page.url))
  assert.equal(urls.filter(url => url === duplicateUrl).length, 2)
})

test("未知标签组颜色降级为 grey", () => {
  const state = buildLiveState({
    sourceId: "source",
    groups: [{ id: 10, title: "未知颜色", color: "black", collapsed: false }],
    windows: [
      {
        id: 1,
        type: "normal",
        incognito: false,
        tabs: [tab(1, 1, 10, 0, "网页", "https://example.com")]
      }
    ]
  })

  assert.equal(state.windows[0].groups[0].color, "grey")
})

test("防抖只执行最后一次调用", () => {
  const callbacks = new Map()
  let nextId = 0
  const timers = {
    setTimeout(callback) {
      nextId += 1
      callbacks.set(nextId, callback)
      return nextId
    },
    clearTimeout(id) {
      callbacks.delete(id)
    }
  }
  const values = []
  const debounced = createDebouncer(value => values.push(value), 400, timers)

  debounced("first")
  debounced("second")
  debounced("last")

  assert.equal(callbacks.size, 1)
  callbacks.values().next().value()
  assert.deepEqual(values, ["last"])
})

test("网址协议白名单", () => {
  assert.equal(isSupportedUrl("https://example.com"), true)
  assert.equal(isSupportedUrl("http://localhost:3000"), true)
  assert.equal(isSupportedUrl("file:///tmp/private"), false)
  assert.equal(isSupportedUrl("chrome://settings"), false)
  assert.equal(isSupportedUrl("not a url"), false)
})

function tab(id, windowId, groupId, index, title, url) {
  return {
    id,
    windowId,
    groupId,
    index,
    title,
    url,
    pinned: false,
    active: false,
    audible: false,
    discarded: false,
    incognito: false
  }
}
