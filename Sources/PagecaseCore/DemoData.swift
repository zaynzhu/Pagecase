import Foundation

public enum DemoData {
  public static func liveStates(referenceDate: Date = Date()) -> [LiveState] {
    [
      makeState(
        sourceId: "demo-chrome-main",
        label: "Chrome · 日常",
        capturedAt: referenceDate,
        startingTabId: 100,
        windowCount: 2
      ),
      makeState(
        sourceId: "demo-chrome-archive",
        label: "Chrome · 研究",
        capturedAt: referenceDate.addingTimeInterval(-95),
        startingTabId: 500,
        windowCount: 1
      )
    ]
  }

  public static func snapshots(referenceDate: Date = Date()) -> [SavedSnapshot] {
    let states = liveStates(referenceDate: referenceDate)
    let groupWindow = states[0].windows[0]
    let savedGroup = groupWindow.groups[0]
    let earlierGroup = TabGroup(
      id: savedGroup.id,
      title: savedGroup.title,
      color: savedGroup.color,
      collapsed: savedGroup.collapsed,
      order: savedGroup.order,
      tabs: Array(savedGroup.tabs.dropLast())
    )
    return [
      SavedSnapshot(
        id: "demo-snapshot-development-group",
        name: "开发 · 最近保存",
        createdAt: referenceDate.addingTimeInterval(-3_600),
        sourceId: states[0].source.id,
        scope: .group,
        windows: [
          BrowserWindow(
            id: groupWindow.id,
            order: groupWindow.order,
            focused: groupWindow.focused,
            groups: [savedGroup],
            ungroupedTabs: []
          )
        ]
      ),
      SavedSnapshot(
        id: "demo-snapshot-july",
        name: "七月的工具研究",
        createdAt: referenceDate.addingTimeInterval(-86_400 * 4),
        sourceId: states[0].source.id,
        windows: states[0].windows
      ),
      SavedSnapshot(
        id: "demo-snapshot-development-group-early",
        name: "开发 · 较早版本",
        createdAt: referenceDate.addingTimeInterval(-86_400 * 7),
        sourceId: states[0].source.id,
        scope: .group,
        windows: [
          BrowserWindow(
            id: groupWindow.id,
            order: groupWindow.order,
            focused: groupWindow.focused,
            groups: [earlierGroup],
            ungroupedTabs: []
          )
        ]
      ),
      SavedSnapshot(
        id: "demo-snapshot-trip",
        name: "云南路线资料",
        createdAt: referenceDate.addingTimeInterval(-86_400 * 12),
        sourceId: states[1].source.id,
        windows: states[1].windows
      )
    ]
  }

  public static func performanceState(tabCount: Int = 500, referenceDate: Date = Date()) -> LiveState {
    let tabs = (0..<tabCount).map { index in
      PageItem(
        id: 10_000 + index,
        windowId: 900,
        groupId: 901,
        index: index,
        title: "性能测试网页 \(index + 1)",
        url: "https://example.com/library/page-\(index + 1)"
      )
    }
    let group = TabGroup(
      id: 901,
      title: "性能测试",
      color: .blue,
      collapsed: false,
      order: 0,
      tabs: tabs
    )
    return LiveState(
      source: BrowserSource(
        id: "demo-performance",
        label: "Chrome · 500 个网页",
        capturedAt: referenceDate
      ),
      windows: [
        BrowserWindow(id: 900, order: 0, focused: true, groups: [group], ungroupedTabs: [])
      ]
    )
  }

  public static func seedIfNeeded(paths: AppPaths, performance: Bool = false) throws {
    let repository = try SnapshotRepository(paths: paths)
    if try repository.loadLiveStates().isEmpty {
      let states = performance ? [performanceState()] : liveStates()
      for state in states {
        try repository.saveLiveState(state)
      }
    }

    if !performance, try repository.loadSnapshots().isEmpty {
      for snapshot in snapshots() {
        try repository.saveSnapshot(snapshot)
      }
    }
  }

  private static func makeState(
    sourceId: String,
    label: String,
    capturedAt: Date,
    startingTabId: Int,
    windowCount: Int
  ) -> LiveState {
    let groupBlueprints: [(String, ChromeGroupColor, [String], [String])] = [
      (
        "开发",
        .blue,
        ["GitHub · Pull requests", "Prisma ORM 文档", "本地项目"],
        ["https://github.com/pulls", "https://www.prisma.io/docs", "http://localhost:3000"]
      ),
      (
        "AI 工具",
        .green,
        ["OpenAI 文档", "Anthropic 文档", "模型评测"],
        ["https://platform.openai.com/docs", "https://docs.anthropic.com", "https://example.com/model-review"]
      ),
      (
        "",
        .yellow,
        ["稍后阅读", "设计参考", "性能分析"],
        ["https://example.com/read-later", "https://example.com/design-reference", "https://example.com/performance"]
      )
    ]

    var nextTabId = startingTabId
    var nextGroupId = startingTabId + 1_000
    var windows: [BrowserWindow] = []

    for windowOrder in 0..<windowCount {
      let windowId = startingTabId + 2_000 + windowOrder
      var groups: [TabGroup] = []

      for (groupIndex, blueprint) in groupBlueprints.enumerated() {
        let groupId = nextGroupId
        nextGroupId += 1
        let tabs = zip(blueprint.2, blueprint.3).enumerated().map { tabIndex, pair in
          defer { nextTabId += 1 }
          return PageItem(
            id: nextTabId,
            windowId: windowId,
            groupId: groupId,
            index: groupIndex * 10 + tabIndex,
            title: pair.0,
            url: pair.1,
            pinned: windowOrder == 0 && groupIndex == 0 && tabIndex == 0,
            active: windowOrder == 0 && groupIndex == 0 && tabIndex == 1,
            audible: windowOrder == 0 && groupIndex == 1 && tabIndex == 2,
            discarded: windowOrder == 1 && groupIndex == 2 && tabIndex == 1
          )
        }
        groups.append(
          TabGroup(
            id: groupId,
            title: blueprint.0,
            color: blueprint.1,
            collapsed: groupIndex == 2,
            order: groupIndex,
            tabs: tabs
          )
        )
      }

      let duplicateURL = "https://example.com/shared-context"
      let ungrouped = [
        PageItem(
          id: nextTabId,
          windowId: windowId,
          groupId: nil,
          index: 40,
          title: windowOrder == 0 ? "日历" : "相同网址，不同语境",
          url: windowOrder == 0 ? "https://calendar.google.com" : duplicateURL
        ),
        PageItem(
          id: nextTabId + 1,
          windowId: windowId,
          groupId: nil,
          index: 41,
          title: "相同网址，保留重复",
          url: duplicateURL
        )
      ]
      nextTabId += 2

      windows.append(
        BrowserWindow(
          id: windowId,
          order: windowOrder,
          focused: windowOrder == 0,
          groups: groups,
          ungroupedTabs: ungrouped
        )
      )
    }

    return LiveState(
      source: BrowserSource(id: sourceId, label: label, capturedAt: capturedAt),
      windows: windows
    )
  }
}
