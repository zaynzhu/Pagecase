import Foundation
import PagecaseCore

enum CheckFailure: LocalizedError {
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .failed(let message):
      return message
    }
  }
}

@discardableResult
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws -> Int {
  guard try condition() else {
    throw CheckFailure.failed(message)
  }
  return 1
}

func withTemporaryPaths<T>(_ operation: (AppPaths) throws -> T) throws -> T {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("PagecaseChecks-\(UUID().uuidString)", isDirectory: true)
  defer {
    if FileManager.default.fileExists(atPath: root.path) {
      try? FileManager.default.removeItem(at: root)
    }
  }
  return try operation(AppPaths(root: root))
}

func runChecks() throws -> Int {
  let referenceDate = Date(timeIntervalSince1970: 1_754_486_400)
  let states = DemoData.liveStates(referenceDate: referenceDate)
  guard let firstState = states.first else {
    throw CheckFailure.failed("演示数据缺少实时现场")
  }

  var passed = 0
  let freshnessSource = BrowserSource(
    id: "freshness-source",
    label: "Chrome",
    capturedAt: referenceDate
  )
  passed += try check(
    freshnessSource.isFresh(at: referenceDate.addingTimeInterval(30)),
    "来源在 30 秒边界内被误判为过期"
  )
  passed += try check(
    !freshnessSource.isFresh(at: referenceDate.addingTimeInterval(30.001)),
    "过期来源仍被误判为已连接"
  )
  passed += try check(states.count == 2, "浏览器来源数量不正确")
  passed += try check(firstState.windows.count == 2, "窗口数量不正确")
  passed += try check(firstState.groupCount == 6, "标签组数量不正确")
  passed += try check(firstState.tabCount == 22, "网页数量不正确")
  passed += try check(
    firstState.windows[0].groups[2].displayTitle == "未命名标签组",
    "未命名标签组显示错误"
  )

  let duplicateURL = "https://example.com/shared-context"
  let duplicateCount = firstState.windows
    .flatMap(\.ungroupedTabs)
    .filter { $0.url == duplicateURL }
    .count
  passed += try check(duplicateCount == 3, "重复网址被意外合并")

  let restoreDuplicateURL = "https://example.com/restore-duplicate"
  let restoreGroup = TabGroup(
    id: 20,
    title: "恢复预览",
    color: .blue,
    collapsed: false,
    order: 0,
    tabs: [
      PageItem(
        id: 1,
        windowId: 10,
        groupId: 20,
        index: 0,
        title: "重复一",
        url: restoreDuplicateURL
      ),
      PageItem(
        id: 2,
        windowId: 10,
        groupId: 20,
        index: 1,
        title: "重复二",
        url: restoreDuplicateURL
      ),
      PageItem(
        id: 3,
        windowId: 10,
        groupId: 20,
        index: 2,
        title: "只在快照",
        url: "https://example.com/restore-snapshot-only"
      )
    ]
  )
  let restoreState = LiveState(
    source: BrowserSource(
      id: "restore-chrome",
      label: "Chrome · 恢复测试",
      capturedAt: referenceDate
    ),
    windows: [
      BrowserWindow(
        id: 30,
        order: 0,
        focused: true,
        groups: [],
        ungroupedTabs: [
          PageItem(
            id: 4,
            windowId: 30,
            groupId: nil,
            index: 0,
            title: "当前只有一个副本",
            url: restoreDuplicateURL
          )
        ]
      )
    ]
  )
  let restorePreview = GroupRestorePreviewBuilder.make(
    group: restoreGroup,
    sourceId: restoreState.source.id,
    liveStates: [restoreState]
  )
  passed += try check(restorePreview.pageCount == 3, "恢复预览遗漏快照网页")
  passed += try check(
    restorePreview.alreadyOpenPageCount == 1,
    "恢复预览没有按重复网址数量匹配当前 Chrome"
  )
  let safariRestoreImpostor = LiveState(
    source: BrowserSource(
      id: restoreState.source.id,
      kind: .safari,
      label: "Safari",
      capturedAt: referenceDate
    ),
    windows: restoreState.windows
  )
  passed += try check(
    GroupRestorePreviewBuilder.make(
      group: restoreGroup,
      sourceId: restoreState.source.id,
      liveStates: [safariRestoreImpostor]
    ).alreadyOpenPageCount == 0,
    "Safari 网页被错误计入 Chrome 恢复预览"
  )
  passed += try check(restoreGroup.tabs.count == 3, "恢复预览意外去重快照网页")

  let partialGroup = TabGroup(
    id: restoreGroup.id,
    title: restoreGroup.title,
    color: restoreGroup.color,
    collapsed: restoreGroup.collapsed,
    order: restoreGroup.order,
    tabs: [restoreGroup.tabs[0]]
  )
  let partialPresence = SnapshotPresenceEvaluator.evaluate(
    group: restoreGroup,
    sourceId: restoreState.source.id,
    liveStates: [
      LiveState(
        source: restoreState.source,
        windows: [
          BrowserWindow(
            id: 10,
            order: 0,
            focused: true,
            groups: [partialGroup],
            ungroupedTabs: []
          )
        ]
      )
    ],
    at: referenceDate
  )
  passed += try check(
    partialPresence.state == .partiallyOpen
      && partialPresence.openPageCount == 1
      && partialPresence.closedPageCount == 2,
    "Chrome 快照在场状态没有按重复网址数量计算"
  )
  let allOpenPresence = SnapshotPresenceEvaluator.evaluate(
    group: restoreGroup,
    sourceId: restoreState.source.id,
    liveStates: [
      LiveState(
        source: restoreState.source,
        windows: [
          BrowserWindow(
            id: 10,
            order: 0,
            focused: true,
            groups: [restoreGroup],
            ungroupedTabs: []
          )
        ]
      )
    ],
    at: referenceDate
  )
  passed += try check(
    allOpenPresence.state == .allOpen
      && allOpenPresence.openPageCount == 3
      && allOpenPresence.groupLocation == .original,
    "完整存在的 Chrome 快照网页没有被识别"
  )
  let movedGroupId = restoreGroup.id + 1_000
  let movedGroupTabs = restoreGroup.tabs.enumerated().map { index, page in
    PageItem(
      id: page.id + 1_000,
      windowId: 10,
      groupId: movedGroupId,
      index: index,
      title: page.title,
      url: page.url
    )
  }
  let originalGroupMissingPresence = SnapshotPresenceEvaluator.evaluate(
    group: restoreGroup,
    sourceId: restoreState.source.id,
    liveStates: [
      LiveState(
        source: restoreState.source,
        windows: [
          BrowserWindow(
            id: 10,
            order: 0,
            focused: true,
            groups: [
              TabGroup(
                id: movedGroupId,
                title: restoreGroup.title,
                color: restoreGroup.color,
                collapsed: false,
                order: 0,
                tabs: movedGroupTabs
              )
            ],
            ungroupedTabs: []
          )
        ]
      )
    ],
    at: referenceDate
  )
  passed += try check(
    originalGroupMissingPresence.state == .noneOpen,
    "其他标签组中的相同网页被误报为原标签组仍存在"
  )
  let restoredGroupPresence = SnapshotPresenceEvaluator.evaluate(
    group: restoreGroup,
    sourceId: restoreState.source.id,
    restoredGroupId: movedGroupId,
    liveStates: [
      LiveState(
        source: restoreState.source,
        windows: [
          BrowserWindow(
            id: 10,
            order: 0,
            focused: true,
            groups: [
              TabGroup(
                id: movedGroupId,
                title: restoreGroup.title,
                color: restoreGroup.color,
                collapsed: false,
                order: 0,
                tabs: movedGroupTabs
              )
            ],
            ungroupedTabs: []
          )
        ]
      )
    ],
    at: referenceDate
  )
  passed += try check(
    restoredGroupPresence.state == .allOpen
      && restoredGroupPresence.groupLocation == .restored,
    "恢复创建的新标签组没有被持续识别"
  )
  let noneOpenPresence = SnapshotPresenceEvaluator.evaluate(
    pages: restoreGroup.tabs,
    sourceId: restoreState.source.id,
    liveStates: [LiveState(source: restoreState.source, windows: [])],
    at: referenceDate
  )
  passed += try check(
    noneOpenPresence.state == .noneOpen && noneOpenPresence.openPageCount == 0,
    "已经离开 Chrome 的快照网页没有被识别"
  )
  let stalePresence = SnapshotPresenceEvaluator.evaluate(
    group: restoreGroup,
    sourceId: restoreState.source.id,
    liveStates: [
      LiveState(
        source: BrowserSource(
          id: restoreState.source.id,
          label: restoreState.source.label,
          capturedAt: referenceDate.addingTimeInterval(-31)
        ),
        windows: restoreState.windows
      )
    ],
    at: referenceDate
  )
  passed += try check(
    stalePresence.state == .unavailable,
    "过期 Chrome 来源被误报为可靠在场状态"
  )
  passed += try check(
    SnapshotPresenceEvaluator.evaluate(
      group: restoreGroup,
      sourceId: restoreState.source.id,
      liveStates: [safariRestoreImpostor],
      at: referenceDate
    ).state == .unavailable,
    "Safari 现场被错误用于 Chrome 快照在场判断"
  )

  let snapshots = DemoData.snapshots(referenceDate: referenceDate)
  let chromeOverview = ChromeLibraryOverviewBuilder.make(
    snapshots: snapshots,
    liveStates: states,
    at: referenceDate
  )
  let libraryItems = SnapshotLibraryOrganizer.organize(snapshots)
  let developmentSeries = SnapshotLibraryOrganizer.groupSeries(
    containing: "demo-snapshot-development-group-early",
    in: snapshots
  )
  passed += try check(snapshots.count == 5, "跨浏览器演示快照数量不正确")
  passed += try check(
    chromeOverview.totalCount == 4,
    "Chrome 收纳总览混入了 Safari 合集"
  )
  passed += try check(libraryItems.count == 4, "标签组版本没有收纳为一个资料库条目")
  passed += try check(developmentSeries?.title == "开发", "标签组版本序列标题错误")
  passed += try check(
    developmentSeries?.snapshots.map(\.id) == [
      "demo-snapshot-development-group",
      "demo-snapshot-development-group-early"
    ],
    "标签组版本没有按时间倒序排列"
  )
  passed += try check(
    developmentSeries?.snapshots.map(\.tabCount) == [3, 2],
    "标签组版本内容被意外合并"
  )
  passed += try check(
    libraryItems.filter { item in
      if case .snapshot = item {
        return true
      }
      return false
    }.count == 3,
    "独立快照或 Safari 合集被错误归入版本序列"
  )
  guard let safariSnapshot = snapshots.first(where: { $0.sourceKind == .safari }) else {
    throw CheckFailure.failed("演示数据缺少 Safari 合集")
  }
  passed += try check(
    safariSnapshot.scope == .collection
      && safariSnapshot.sourceId == SafariCollectionBuilder.sourceId
      && safariSnapshot.sourceLabel == SafariCollectionBuilder.sourceLabel,
    "Safari 合集来源信息不完整"
  )
  passed += try check(
    SnapshotPresenceEvaluator.evaluate(
      snapshot: safariSnapshot,
      liveStates: states,
      at: referenceDate
    ) == nil,
    "Safari 合集被错误赋予 Chrome 在场状态"
  )
  let emptyChromeSnapshot = SavedSnapshot(
    id: "empty-presence-snapshot",
    name: "空快照",
    createdAt: referenceDate,
    sourceId: restoreState.source.id,
    sourceLabel: restoreState.source.label,
    windows: []
  )
  passed += try check(
    SnapshotPresenceEvaluator.evaluate(
      snapshot: emptyChromeSnapshot,
      liveStates: states,
      at: referenceDate
    ) == nil,
    "空 Chrome 快照显示了没有意义的在场状态"
  )
  passed += try check(
    snapshots.filter { $0.sourceKind == .chrome }.count == 4
      && snapshots.filter { $0.sourceKind == .safari }.count == 1,
    "Chrome 快照与 Safari 合集没有保持独立来源"
  )
  passed += try check(
    safariSnapshot.windows.count == 1
      && safariSnapshot.windows[0].groups.isEmpty
      && safariSnapshot.tabCount == 4,
    "Safari 合集没有只保存当前窗口网页"
  )
  passed += try check(
    safariSnapshot.windows[0].ungroupedTabs.filter {
      $0.url == "https://example.com/safari-reading"
    }.count == 2,
    "Safari 合集中的重复网址被意外合并"
  )
  let safariResults = SearchEngine.search(
    query: "WebKit",
    liveStates: [],
    snapshots: [safariSnapshot]
  )
  passed += try check(
    safariResults.first?.sourceKind == .safari
      && safariResults.first?.sourceLabel == SafariCollectionBuilder.sourceLabel,
    "Safari 搜索结果缺少明确浏览器来源"
  )
  let allBrowserResults = SearchEngine.search(
    query: "example.com",
    liveStates: states,
    snapshots: snapshots
  )
  let chromeOnlyResults = SearchEngine.search(
    query: "example.com",
    liveStates: states,
    snapshots: snapshots,
    browserFilter: .chrome
  )
  let safariOnlyResults = SearchEngine.search(
    query: "example.com",
    liveStates: states,
    snapshots: snapshots,
    browserFilter: .safari
  )
  passed += try check(
    Set(allBrowserResults.map(\.sourceKind)) == [.chrome, .safari],
    "全部浏览器搜索没有同时保留 Chrome 与 Safari"
  )
  passed += try check(
    !chromeOnlyResults.isEmpty
      && chromeOnlyResults.allSatisfy { $0.sourceKind == .chrome },
    "Chrome 搜索筛选混入了 Safari 合集"
  )
  passed += try check(
    !safariOnlyResults.isEmpty
      && safariOnlyResults.allSatisfy { $0.sourceKind == .safari },
    "Safari 搜索筛选混入了 Chrome 资料"
  )
  passed += try withTemporaryPaths { paths in
    var localPassed = 0
    let repository = try SnapshotRepository(paths: paths)
    for snapshot in snapshots {
      try repository.saveSnapshot(snapshot)
    }
    let chromeURL = paths.root.appendingPathComponent("chrome-library.json")
    let safariURL = paths.root.appendingPathComponent("safari-library.json")
    let mixedURL = paths.root.appendingPathComponent("mixed-library.json")
    try repository.exportLibrary(
      to: chromeURL,
      applicationVersion: "check",
      browserKind: .chrome
    )
    try repository.exportLibrary(
      to: safariURL,
      applicationVersion: "check",
      browserKind: .safari
    )
    try repository.exportLibrary(to: mixedURL, applicationVersion: "check")
    let decoder = PagecaseJSON.makeDecoder()
    let chromeExport = try decoder.decode(
      LibraryExport.self,
      from: Data(contentsOf: chromeURL)
    )
    let safariExport = try decoder.decode(
      LibraryExport.self,
      from: Data(contentsOf: safariURL)
    )
    localPassed += try check(
      chromeExport.snapshots.count == 4
        && chromeExport.snapshots.allSatisfy { $0.sourceKind == .chrome },
      "Chrome 单独导出混入了 Safari 合集"
    )
    localPassed += try check(
      safariExport.snapshots.count == 1
        && safariExport.snapshots.allSatisfy { $0.sourceKind == .safari },
      "Safari 单独导出混入了 Chrome 快照"
    )
    let beforePreview = try repository.loadSnapshots()
    let preview = try repository.inspectLibraryImport(from: mixedURL)
    localPassed += try check(
      preview.snapshotCount == 5
        && preview.summary(for: .chrome)?.snapshotCount == 4
        && preview.summary(for: .safari)?.snapshotCount == 1,
      "导入预览没有按浏览器准确汇总"
    )
    localPassed += try check(
      preview.summary(for: .chrome)?.idConflictCount == 4
        && preview.summary(for: .safari)?.idConflictCount == 1,
      "导入预览没有提前识别本地标识冲突"
    )
    localPassed += try check(
      try repository.loadSnapshots() == beforePreview,
      "只读导入预览意外修改了本地资料"
    )
    localPassed += try withTemporaryPaths { importPaths in
      var importPassed = 0
      let importRepository = try SnapshotRepository(paths: importPaths)
      let emptySelection = try importRepository.importLibrary(
        from: mixedURL,
        browserKinds: []
      )
      importPassed += try check(
        emptySelection.isEmpty && importRepository.loadSnapshots().isEmpty,
        "空来源选择仍然写入了导入资料"
      )
      let safariImport = try importRepository.importLibrary(
        from: mixedURL,
        browserKinds: [.safari]
      )
      importPassed += try check(
        safariImport.count == 1
          && safariImport.allSatisfy { $0.sourceKind == .safari },
        "Safari 专属导入混入了 Chrome 快照"
      )
      let chromeImport = try importRepository.importLibrary(
        from: mixedURL,
        browserKinds: [.chrome]
      )
      importPassed += try check(
        chromeImport.count == 4
          && chromeImport.allSatisfy { $0.sourceKind == .chrome },
        "Chrome 专属导入混入了 Safari 合集"
      )
      importPassed += try check(
        try importRepository.loadSnapshots().count == 5,
        "分区导入完成后的资料数量不正确"
      )
      return importPassed
    }
    return localPassed
  }
  guard let series = developmentSeries,
        let seriesWindow = series.latestSnapshot.windows.first,
        let seriesGroup = seriesWindow.groups.first else {
    throw CheckFailure.failed("标签组版本序列缺少语境夹具")
  }
  let renamedSeriesGroup = TabGroup(
    id: seriesGroup.id,
    title: "另一组开发资料",
    color: seriesGroup.color,
    collapsed: seriesGroup.collapsed,
    order: seriesGroup.order,
    tabs: seriesGroup.tabs
  )
  let renamedSeriesSnapshot = SavedSnapshot(
    id: "renamed-series-context",
    name: "名称变化后的快照",
    createdAt: referenceDate.addingTimeInterval(-120),
    sourceId: series.latestSnapshot.sourceId,
    scope: .group,
    windows: [
      BrowserWindow(
        id: seriesWindow.id,
        order: seriesWindow.order,
        focused: seriesWindow.focused,
        groups: [renamedSeriesGroup],
        ungroupedTabs: []
      )
    ]
  )
  passed += try check(
    SnapshotLibraryOrganizer.organize([
      series.latestSnapshot,
      renamedSeriesSnapshot
    ]).count == 2,
    "名称变化后的标签组被错误归入原版本序列"
  )
  let recoloredSeriesGroup = TabGroup(
    id: seriesGroup.id,
    title: seriesGroup.title,
    color: .red,
    collapsed: seriesGroup.collapsed,
    order: seriesGroup.order,
    tabs: seriesGroup.tabs
  )
  let recoloredSeriesSnapshot = SavedSnapshot(
    id: "recolored-series-context",
    name: "颜色变化后的快照",
    createdAt: referenceDate.addingTimeInterval(-180),
    sourceId: series.latestSnapshot.sourceId,
    scope: .group,
    windows: [
      BrowserWindow(
        id: seriesWindow.id,
        order: seriesWindow.order,
        focused: seriesWindow.focused,
        groups: [recoloredSeriesGroup],
        ungroupedTabs: []
      )
    ]
  )
  passed += try check(
    SnapshotLibraryOrganizer.organize([
      series.latestSnapshot,
      recoloredSeriesSnapshot
    ]).count == 2,
    "颜色变化后的标签组被错误归入原版本序列"
  )
  guard let exactSnapshot = snapshots.first(where: {
    $0.sourceId == firstState.source.id && $0.scope == .fullState
  }),
        let firstWindow = firstState.windows.first else {
    throw CheckFailure.failed("演示数据缺少覆盖检查夹具")
  }
  let exactCoverage = SnapshotCoverageEvaluator.evaluate(
    liveState: firstState,
    snapshots: [exactSnapshot]
  )
  passed += try check(exactCoverage.isComplete, "完整快照未覆盖当前网页")

  var reducedWindows = firstState.windows
  reducedWindows[0] = BrowserWindow(
    id: firstWindow.id,
    order: firstWindow.order,
    focused: firstWindow.focused,
    groups: firstWindow.groups,
    ungroupedTabs: Array(firstWindow.ungroupedTabs.dropLast())
  )
  let reducedState = LiveState(source: firstState.source, windows: reducedWindows)
  passed += try check(
    SnapshotCoverageEvaluator.evaluate(
      liveState: reducedState,
      snapshots: [exactSnapshot]
    ).isComplete,
    "关闭部分网页后原快照不再覆盖剩余网页"
  )

  let incompleteSnapshot = SavedSnapshot(
    id: "incomplete-coverage",
    name: "少一个重复网址",
    createdAt: referenceDate,
    sourceId: firstState.source.id,
    windows: reducedWindows
  )
  let incompleteCoverage = SnapshotCoverageEvaluator.evaluate(
    liveState: firstState,
    snapshots: [incompleteSnapshot]
  )
  passed += try check(
    incompleteCoverage.uncoveredPageCount == 1,
    "重复网址的缺失数量判断错误"
  )
  var changedContextWindows = firstState.windows
  var changedGroups = firstWindow.groups
  guard let firstGroup = changedGroups.first else {
    throw CheckFailure.failed("演示数据缺少标签组夹具")
  }
  passed += try check(
    SnapshotCoverageEvaluator.evaluate(
      group: firstGroup,
      sourceId: firstState.source.id,
      snapshots: [exactSnapshot]
    ).isComplete,
    "完整快照未覆盖实时标签组"
  )
  changedGroups[0] = TabGroup(
    id: firstGroup.id,
    title: "其他语境",
    color: firstGroup.color,
    collapsed: firstGroup.collapsed,
    order: firstGroup.order,
    tabs: firstGroup.tabs
  )
  changedContextWindows[0] = BrowserWindow(
    id: firstWindow.id,
    order: firstWindow.order,
    focused: firstWindow.focused,
    groups: changedGroups,
    ungroupedTabs: firstWindow.ungroupedTabs
  )
  let changedContextSnapshot = SavedSnapshot(
    id: "changed-context-coverage",
    name: "标签组不同",
    sourceId: firstState.source.id,
    windows: changedContextWindows
  )
  passed += try check(
    SnapshotCoverageEvaluator.evaluate(
      liveState: firstState,
      snapshots: [changedContextSnapshot]
    ).uncoveredPageCount == firstGroup.tabs.count,
    "不同标签组语境被误认为已经覆盖"
  )
  passed += try check(
    SnapshotCoverageEvaluator.evaluate(
      liveState: firstState,
      snapshots: [incompleteSnapshot, exactSnapshot]
    ).snapshot?.id == exactSnapshot.id,
    "未优先选择覆盖更完整的快照"
  )
  let wrongSourceSnapshot = SavedSnapshot(
    id: "wrong-source-coverage",
    name: "其他来源",
    sourceId: "other-source",
    windows: firstState.windows
  )
  passed += try check(
    SnapshotCoverageEvaluator.evaluate(
      liveState: firstState,
      snapshots: [wrongSourceSnapshot]
    ).uncoveredPageCount == firstState.tabCount,
    "其他来源的快照被误认为可用覆盖"
  )
  let safariImpostor = SavedSnapshot(
    id: "safari-impostor-coverage",
    name: "不应覆盖 Chrome",
    sourceId: firstState.source.id,
    sourceKind: .safari,
    sourceLabel: "Safari",
    windows: firstState.windows
  )
  passed += try check(
    SnapshotCoverageEvaluator.evaluate(
      liveState: firstState,
      snapshots: [safariImpostor]
    ).snapshot == nil,
    "Safari 内容被错误用于 Chrome 保存覆盖"
  )

  passed += try check(
    SearchEngine.search(query: "Prisma", liveStates: states, snapshots: []).first?.title
      == "Prisma ORM 文档",
    "标题搜索失败"
  )
  passed += try check(
    !SearchEngine.search(query: "AI 工具", liveStates: states, snapshots: []).isEmpty,
    "标签组搜索失败"
  )
  passed += try check(
    !SearchEngine.search(query: "github.com", liveStates: states, snapshots: []).isEmpty,
    "域名搜索失败"
  )
  passed += try check(
    !SearchEngine.search(query: "七月的工具", liveStates: [], snapshots: snapshots).isEmpty,
    "快照名称搜索失败"
  )

  let groupResults = SearchEngine.search(
    query: "AI 工具",
    liveStates: states,
    snapshots: snapshots
  )
  passed += try check(
    groupResults.first?.target == .group && groupResults.first?.kind == .live,
    "标签组没有排在其成员网页之前"
  )
  passed += try check(
    groupResults.first?.title == "AI 工具" && groupResults.first?.pageCount == 3,
    "标签组搜索结果摘要不完整"
  )
  passed += try check(
    groupResults.first?.windowId != nil && groupResults.first?.groupId != nil,
    "实时标签组搜索结果缺少定位信息"
  )
  passed += try check(
    groupResults.contains { $0.target == .page },
    "标签组搜索遗漏了成员网页"
  )
  let snapshotGroupResult = groupResults.first {
    $0.target == .group && $0.kind == .snapshot
  }
  passed += try check(
    snapshotGroupResult?.snapshotId != nil
      && snapshotGroupResult?.windowId != nil
      && snapshotGroupResult?.groupId != nil,
    "快照标签组搜索结果缺少定位信息"
  )
  passed += try check(
    snapshotGroupResult?.url == nil,
    "标签组搜索结果不应伪装成单个网页"
  )

  let duplicateResults = SearchEngine.search(
    query: "shared-context",
    liveStates: states,
    snapshots: snapshots
  )
  passed += try check(
    Set(duplicateResults.map(\.id)).count == duplicateResults.count,
    "搜索结果标识发生冲突"
  )

  let legacyEncoded = try PagecaseJSON.makeEncoder().encode(exactSnapshot)
  guard var legacyObject = try JSONSerialization.jsonObject(with: legacyEncoded)
    as? [String: Any] else {
    throw CheckFailure.failed("旧快照兼容夹具生成失败")
  }
  legacyObject.removeValue(forKey: "scope")
  legacyObject.removeValue(forKey: "sourceKind")
  legacyObject.removeValue(forKey: "sourceLabel")
  let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
  let legacySnapshot = try PagecaseJSON.makeDecoder().decode(
    SavedSnapshot.self,
    from: legacyData
  )
  passed += try check(
    legacySnapshot.scope == .fullState
      && legacySnapshot.sourceKind == .chrome
      && legacySnapshot.sourceLabel == "Chrome",
    "旧快照未默认识别为 Chrome 完整现场"
  )

  passed += try withTemporaryPaths { paths in
    var localPassed = 0
    let repository = try SnapshotRepository(paths: paths)
    let groupSnapshot = try repository.createGroupSnapshot(
      from: firstGroup,
      in: firstWindow,
      sourceId: firstState.source.id,
      name: "  开发资料  ",
      now: referenceDate
    )
    let persisted = try repository.loadSnapshots().first
    localPassed += try check(groupSnapshot.scope == .group, "标签组快照类型错误")
    localPassed += try check(groupSnapshot.name == "开发资料", "标签组快照名称未清理")
    localPassed += try check(
      groupSnapshot.windows.count == 1
        && groupSnapshot.windows[0].groups == [firstGroup]
        && groupSnapshot.windows[0].ungroupedTabs.isEmpty,
      "标签组快照包含了选中组以外的内容"
    )
    localPassed += try check(persisted == groupSnapshot, "标签组快照落盘核对失败")
    let coverage = SnapshotCoverageEvaluator.evaluate(
      group: firstGroup,
      sourceId: firstState.source.id,
      snapshots: [groupSnapshot]
    )
    localPassed += try check(
      coverage.isComplete
        && coverage.windowId == firstWindow.id
        && coverage.groupId == firstGroup.id,
      "标签组快照无法定位对应保存内容"
    )
    let fullStateCoverage = SnapshotCoverageEvaluator.evaluate(
      liveState: firstState,
      snapshots: [groupSnapshot]
    )
    localPassed += try check(
      fullStateCoverage.snapshot == nil
        && fullStateCoverage.uncoveredPageCount == firstState.tabCount,
      "标签组快照被误认为完整现场快照"
    )
    let exportURL = paths.root.appendingPathComponent("group-library.json")
    try repository.exportLibrary(to: exportURL, applicationVersion: "check")
    let imported = try repository.importLibrary(from: exportURL)
    localPassed += try check(
      imported.first?.id != groupSnapshot.id
        && imported.first?.scope == .group
        && repository.loadSnapshots().count == 2,
      "标签组快照导入冲突后没有保留范围"
    )
    return localPassed
  }

  passed += try withTemporaryPaths { paths in
    var localPassed = 0
    let repository = try SnapshotRepository(paths: paths)
    let capture = DemoData.safariCapture(referenceDate: referenceDate)
    let collection = try repository.createSafariCollection(
      from: capture,
      name: "  Safari 阅读  "
    )
    localPassed += try check(
      collection.name == "Safari 阅读"
        && collection.sourceKind == .safari
        && collection.scope == .collection,
      "Safari 合集构建结果错误"
    )
    localPassed += try check(
      try repository.loadSnapshots().first == collection,
      "Safari 合集落盘核对失败"
    )

    let invalidCollection = SavedSnapshot(
      id: "invalid-chrome-collection",
      name: "错误合集",
      sourceId: firstState.source.id,
      scope: .collection,
      windows: [
        BrowserWindow(
          id: 1,
          order: 0,
          focused: true,
          groups: [],
          ungroupedTabs: [
            PageItem(
              id: 1,
              windowId: 1,
              groupId: nil,
              index: 0,
              title: "网页",
              url: "https://example.com"
            )
          ]
        )
      ]
    )
    do {
      try PagecaseValidator.validate(invalidCollection)
      throw CheckFailure.failed("Chrome 内容被错误接受为 Safari 合集")
    } catch is StoreError {
      localPassed += 1
    }

    do {
      _ = try SafariCollectionBuilder.makeSnapshot(
        from: SafariCapture(capturedAt: referenceDate, pages: []),
        name: "空合集"
      )
      throw CheckFailure.failed("空 Safari 合集未被拒绝")
    } catch is StoreError {
      localPassed += 1
    }
    return localPassed
  }

  passed += try withTemporaryPaths { paths in
    var localPassed = 0
    let snapshotsRepository = try SnapshotRepository(paths: paths)
    try snapshotsRepository.saveLiveState(firstState)
    let snapshot = try snapshotsRepository.createSnapshot(from: firstState, name: "开发现场")
    try snapshotsRepository.saveLiveState(DemoData.performanceState(tabCount: 3))
    let saved = try snapshotsRepository.loadSnapshots()
    localPassed += try check(saved.first?.id == snapshot.id, "快照保存失败")
    localPassed += try check(saved.first?.tabCount == firstState.tabCount, "实时更新改写了快照")

    let commandRepository = try CommandRepository(paths: paths)
    let command = BrowserCommand(
      sourceId: firstState.source.id,
      action: .focusTab,
      tabId: 10,
      windowId: 20
    )
    try commandRepository.enqueue(command)
    let pending = try commandRepository.loadPendingCommands()
    localPassed += try check(
      pending.count == 1
        && pending.first?.id == command.id
        && pending.first?.action == command.action,
      "命令入队失败"
    )
    try commandRepository.claim(command)
    let processing = try commandRepository.loadProcessingCommands()
    localPassed += try check(
      processing.count == 1 && processing.first?.id == command.id,
      "命令领取失败"
    )
    let result = BrowserCommandResult(
      id: command.id,
      sourceId: command.sourceId,
      success: true,
      message: "已定位"
    )
    try commandRepository.saveResult(result)
    let savedResult = try commandRepository.loadResult(commandId: command.id)
    localPassed += try check(
      savedResult?.id == result.id
        && savedResult?.sourceId == result.sourceId
        && savedResult?.success == result.success,
      "命令结果保存失败"
    )

    let exportURL = paths.root.appendingPathComponent("library.json")
    try snapshotsRepository.exportLibrary(to: exportURL, applicationVersion: "check")
    let imported = try snapshotsRepository.importLibrary(from: exportURL)
    let afterImport = try snapshotsRepository.loadSnapshots()
    localPassed += try check(imported.count == 1, "资料库导入数量不正确")
    localPassed += try check(
      afterImport.count == 2 && Set(afterImport.map(\.id)).count == 2,
      "导入标识冲突未保留两份快照"
    )

    let invalidPage = PageItem(
      id: 90_001,
      windowId: 90_000,
      groupId: nil,
      index: 0,
      title: "无效页面",
      url: "file:///tmp/private"
    )
    let invalidSnapshot = SavedSnapshot(
      id: "invalid-import",
      name: "无效快照",
      sourceId: firstState.source.id,
      windows: [
        BrowserWindow(
          id: 90_000,
          order: 0,
          focused: false,
          groups: [],
          ungroupedTabs: [invalidPage]
        )
      ]
    )
    let invalidImportURL = paths.root.appendingPathComponent("invalid-library.json")
    try AtomicJSONStore().write(
      LibraryExport(applicationVersion: "check", snapshots: [invalidSnapshot]),
      to: invalidImportURL
    )
    do {
      try snapshotsRepository.importLibrary(from: invalidImportURL)
      throw CheckFailure.failed("损坏资料库未被拒绝")
    } catch is StoreError {
      localPassed += 1
    }
    localPassed += try check(
      try snapshotsRepository.loadSnapshots().count == afterImport.count,
      "损坏资料库造成了部分写入"
    )

    try snapshotsRepository.deleteSnapshot(id: snapshot.id)
    let afterDelete = try snapshotsRepository.loadSnapshots()
    localPassed += try check(
      afterDelete.count == 1 && !afterDelete.contains(where: { $0.id == snapshot.id }),
      "删除快照时未精确移除目标"
    )
    localPassed += try check(
      try snapshotsRepository.loadLiveStates().first?.tabCount == 3,
      "删除快照意外改变了实时现场"
    )

    let preferencesRepository = DisplayPreferencesRepository(paths: paths)
    let collapsedKey = DisplayPreferences.groupKey(
      scope: "live:\(firstState.source.id)",
      windowId: firstWindow.id,
      groupId: firstGroup.id
    )
    let preferences = DisplayPreferences(collapsedGroupKeys: [collapsedKey])
    try preferencesRepository.save(preferences)
    localPassed += try check(
      try preferencesRepository.load() == preferences,
      "标签组折叠状态未持久保存"
    )

    let restoredGroupsRepository = ChromeRestoredGroupRepository(paths: paths)
    let restoredGroupRecord = ChromeRestoredGroupRecord(
      sourceId: firstState.source.id,
      snapshotId: "saved-group",
      originalGroupId: firstGroup.id,
      restoredGroupId: firstGroup.id + 10_000,
      restoredAt: referenceDate
    )
    try restoredGroupsRepository.save(restoredGroupRecord)
    let replacementRecord = ChromeRestoredGroupRecord(
      sourceId: restoredGroupRecord.sourceId,
      snapshotId: restoredGroupRecord.snapshotId,
      originalGroupId: restoredGroupRecord.originalGroupId,
      restoredGroupId: restoredGroupRecord.restoredGroupId + 1,
      restoredAt: referenceDate.addingTimeInterval(1)
    )
    let restoredGroupIndex = try restoredGroupsRepository.save(replacementRecord)
    localPassed += try check(
      restoredGroupIndex.records.count == 1
        && restoredGroupIndex.record(
          sourceId: replacementRecord.sourceId,
          snapshotId: replacementRecord.snapshotId,
          originalGroupId: replacementRecord.originalGroupId
        )?.restoredGroupId == replacementRecord.restoredGroupId,
      "Chrome 恢复组状态没有按快照原子更新"
    )

    return localPassed
  }

  let framed = try NativeMessageFramer.encode(NativeOutboundMessage(type: "pong"))
  let decoded = try NativeMessageFramer.decode(NativeOutboundMessage.self, from: framed)
  passed += try check(decoded.type == "pong", "Native Messaging 往返失败")

  let restoreCommand = BrowserCommand(
    sourceId: "source",
    action: .restoreGroup,
    groupTitle: "开发",
    groupColor: .blue,
    urls: [
      "https://example.com/first",
      "https://example.com/second"
    ]
  )
  try restoreCommand.validate()
  let restoreFramed = try NativeMessageFramer.encode(
    NativeOutboundMessage(command: restoreCommand)
  )
  let decodedRestore = try NativeMessageFramer.decode(
    NativeOutboundMessage.self,
    from: restoreFramed
  )
  passed += try check(
    decodedRestore.type == "restoreGroup"
      && decodedRestore.groupTitle == "开发"
      && decodedRestore.groupColor == "blue"
      && decodedRestore.urls?.count == 2,
    "恢复整组命令往返失败"
  )

  let successResult = BrowserCommandResult(
    id: restoreCommand.id,
    sourceId: restoreCommand.sourceId,
    success: true,
    message: "已恢复",
    action: .restoreGroup,
    createdTabCount: 2,
    groupCreated: true,
    restoredGroupId: 88
  )
  let successReceipt = GroupRestoreReceiptBuilder.make(
    command: restoreCommand,
    sourceLabel: "Chrome · 日常",
    result: successResult
  )
  passed += try check(
    successReceipt?.status == .success
      && successReceipt?.createdTabCount == 2
      && successReceipt?.groupCreated == true
      && successResult.restoredGroupId == 88,
    "完整恢复结果没有生成成功回执"
  )
  let partialResult = BrowserCommandResult(
    id: restoreCommand.id,
    sourceId: restoreCommand.sourceId,
    success: false,
    message: "Chrome 未能把新标签组成标签组",
    action: .restoreGroup,
    createdTabCount: 2,
    groupCreated: false,
    restoredGroupId: 88,
    failureStage: .groupingTabs
  )
  let partialReceipt = GroupRestoreReceiptBuilder.make(
    command: restoreCommand,
    sourceLabel: "Chrome · 日常",
    result: partialResult
  )
  passed += try check(
    partialReceipt?.status == .partial
      && partialReceipt?.summary.contains("2 / 2") == true
      && partialReceipt?.guidance.contains("不会自动清理或重试") == true,
    "部分恢复结果没有保留已创建数量与不重试边界"
  )
  let timeoutReceipt = GroupRestoreReceiptBuilder.timeout(
    command: restoreCommand,
    sourceLabel: "Chrome · 日常"
  )
  passed += try check(
    timeoutReceipt?.status == .timeout
      && timeoutReceipt?.createdTabCount == nil
      && timeoutReceipt?.guidance.contains("不会自动重试") == true,
    "恢复超时没有生成防重复提示"
  )
  let wrongSourceResult = BrowserCommandResult(
    id: restoreCommand.id,
    sourceId: "other-source",
    success: true,
    message: "不应接收",
    action: .restoreGroup,
    createdTabCount: 2,
    groupCreated: true
  )
  passed += try check(
    GroupRestoreReceiptBuilder.make(
      command: restoreCommand,
      sourceLabel: "Chrome",
      result: wrongSourceResult
    ) == nil,
    "其他 Chrome 来源的结果被错误接收"
  )
  let inboundResult = NativeInboundMessage(
    type: "commandResult",
    commandId: restoreCommand.id,
    sourceId: restoreCommand.sourceId,
    success: false,
    message: "分组失败",
    action: .restoreGroup,
    createdTabCount: 2,
    groupCreated: false,
    restoredGroupId: 88,
    failureStage: .groupingTabs
  )
  let inboundFramed = try NativeMessageFramer.encode(inboundResult)
  let decodedInbound = try NativeMessageFramer.decode(
    NativeInboundMessage.self,
    from: inboundFramed
  )
  passed += try check(
    decodedInbound.action == .restoreGroup
      && decodedInbound.createdTabCount == 2
      && decodedInbound.groupCreated == false
      && decodedInbound.restoredGroupId == 88
      && decodedInbound.failureStage == .groupingTabs,
    "结构化恢复结果往返失败"
  )

  do {
    try BrowserCommand(
      sourceId: "source",
      action: .openUrl,
      url: "file:///tmp/private"
    ).validate()
    throw CheckFailure.failed("非 Web 协议未被拒绝")
  } catch is StoreError {
    passed += 1
  }

  let inconsistentPage = PageItem(
    id: 90_100,
    windowId: 2,
    groupId: nil,
    index: 0,
    title: "窗口不一致",
    url: "https://example.com"
  )
  let inconsistentState = LiveState(
    source: BrowserSource(
      id: "validation-source",
      label: "Chrome",
      capturedAt: referenceDate
    ),
    windows: [
      BrowserWindow(
        id: 1,
        order: 0,
        focused: true,
        groups: [],
        ungroupedTabs: [inconsistentPage]
      )
    ]
  )
  do {
    try PagecaseValidator.validate(inconsistentState)
    throw CheckFailure.failed("不一致的网页上下文未被拒绝")
  } catch is StoreError {
    passed += 1
  }

  passed += try withTemporaryPaths { paths in
    var localPassed = 0
    try paths.createDirectories()
    let bridgeURL = paths.root.appendingPathComponent("PagecaseBridge")
    try Data("#!/bin/sh\n".utf8).write(to: bridgeURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: bridgeURL.path
    )
    let manager = NativeHostManager(
      manifestDirectory: paths.root.appendingPathComponent("NativeMessagingHosts"),
      bridgeURL: bridgeURL
    )
    let extensionId = "abcdefghijklmnopabcdefghijklmnop"

    localPassed += try check(manager.inspect().state == .missing, "Host 缺失状态判断错误")
    let installed = try manager.install(extensionId: extensionId)
    localPassed += try check(
      installed.state == .ready && installed.extensionId == extensionId,
      "Host 安装或核对失败"
    )
    let attributes = try FileManager.default.attributesOfItem(
      atPath: manager.manifestURL.path
    )
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    localPassed += try check(
      permissions & 0o777 == 0o644,
      "Host 清单权限不正确"
    )

    let movedBridgeURL = paths.root.appendingPathComponent("MovedPagecaseBridge")
    try Data("#!/bin/sh\n".utf8).write(to: movedBridgeURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: movedBridgeURL.path
    )
    let movedManager = NativeHostManager(
      manifestDirectory: manager.manifestDirectory,
      bridgeURL: movedBridgeURL
    )
    localPassed += try check(
      movedManager.inspect().state == .invalid,
      "应用移动后的 Host 状态判断错误"
    )

    try manager.uninstall()
    localPassed += try check(manager.inspect().state == .missing, "Host 精确卸载失败")

    do {
      try manager.install(extensionId: "invalid")
      throw CheckFailure.failed("无效扩展标识未被拒绝")
    } catch is StoreError {
      localPassed += 1
    }
    return localPassed
  }

  passed += try withTemporaryPaths { paths in
    var localPassed = 0
    try paths.createDirectories()
    let source = paths.root.appendingPathComponent("BundledExtension", isDirectory: true)
    let destination = paths.root.appendingPathComponent("ChromeExtension", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

    for file in ExtensionPackageManager.requiredFiles {
      try Data("content:\(file)".utf8).write(to: source.appendingPathComponent(file))
    }

    let manager = ExtensionPackageManager(
      sourceDirectory: source,
      destinationDirectory: destination
    )
    localPassed += try check(manager.isSourceAvailable(), "内置扩展完整性判断错误")
    try manager.prepare()
    localPassed += try check(
      ExtensionPackageManager.requiredFiles.allSatisfy { file in
        FileManager.default.fileExists(atPath: destination.appendingPathComponent(file).path)
      },
      "扩展文件准备不完整"
    )

    try FileManager.default.removeItem(
      at: source.appendingPathComponent(ExtensionPackageManager.requiredFiles[0])
    )
    do {
      try manager.prepare()
      throw CheckFailure.failed("不完整扩展来源未被拒绝")
    } catch is StoreError {
      localPassed += 1
    }
    return localPassed
  }

  return passed
}

do {
  let passed = try runChecks()
  print("PagecaseCoreChecks: \(passed) 项检查通过")
} catch {
  FileHandle.standardError.write(Data("PagecaseCoreChecks: \(error.localizedDescription)\n".utf8))
  exit(EXIT_FAILURE)
}
