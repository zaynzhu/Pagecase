import Foundation
@testable import PagecaseCore
import Testing

private let referenceDate = Date(timeIntervalSince1970: 1_754_486_400)

@Test
func sourceFreshnessUsesSharedThirtySecondBoundary() {
  let source = BrowserSource(
    id: "freshness-source",
    label: "Chrome",
    capturedAt: referenceDate
  )

  #expect(source.isFresh(at: referenceDate.addingTimeInterval(30)))
  #expect(!source.isFresh(at: referenceDate.addingTimeInterval(30.001)))
}

@Test
func demoDataKeepsWindowsGroupsAndDuplicateURLs() throws {
  let states = DemoData.liveStates(referenceDate: referenceDate)
  let firstState = try #require(states.first)

  #expect(states.count == 2)
  #expect(firstState.windows.count == 2)
  #expect(firstState.groupCount == 6)
  #expect(firstState.tabCount == 22)
  #expect(firstState.windows[0].groups[2].displayTitle == "未命名标签组")
  #expect(firstState.windows[0].groups[2].collapsed)

  let duplicateURL = "https://example.com/shared-context"
  let duplicates = firstState.windows
    .flatMap(\.ungroupedTabs)
    .filter { $0.url == duplicateURL }
  #expect(duplicates.count == 3)
}

@Test
func snapshotLibraryCollectsGroupVersionsWithoutMergingSnapshots() throws {
  let snapshots = DemoData.snapshots(referenceDate: referenceDate)
  let items = SnapshotLibraryOrganizer.organize(snapshots)
  let firstItem = try #require(items.first)
  guard case .groupSeries(let series) = firstItem else {
    Issue.record("最新的标签组版本没有形成版本序列")
    return
  }

  #expect(snapshots.count == 5)
  #expect(items.count == 4)
  #expect(series.title == "开发")
  #expect(series.snapshots.map(\.id) == [
    "demo-snapshot-development-group",
    "demo-snapshot-development-group-early"
  ])
  #expect(series.snapshots.map(\.tabCount) == [3, 2])
  #expect(
    SnapshotLibraryOrganizer.groupSeries(
      containing: "demo-snapshot-development-group-early",
      in: snapshots
    ) == series
  )
  #expect(items.filter { item in
    if case .snapshot = item {
      return true
    }
    return false
  }.count == 3)
}

@Test
func safariCollectionKeepsBrowserBoundaryAndDuplicateURLs() throws {
  let capture = DemoData.safariCapture(referenceDate: referenceDate)
  let snapshot = try SafariCollectionBuilder.makeSnapshot(
    from: capture,
    name: "  阅读资料  "
  )

  #expect(snapshot.name == "阅读资料")
  #expect(snapshot.sourceKind == .safari)
  #expect(snapshot.sourceId == SafariCollectionBuilder.sourceId)
  #expect(snapshot.sourceLabel == SafariCollectionBuilder.sourceLabel)
  #expect(snapshot.scope == .collection)
  #expect(snapshot.windows.count == 1)
  #expect(snapshot.windows[0].groups.isEmpty)
  #expect(snapshot.tabCount == 4)
  #expect(snapshot.windows[0].ungroupedTabs.filter {
    $0.url == "https://example.com/safari-reading"
  }.count == 2)
  #expect(snapshot.windows[0].ungroupedTabs.first?.active == true)
  try PagecaseValidator.validate(snapshot)
}

@Test
func safariCollectionPersistsAndSearchesAsSafari() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    let snapshot = try repository.createSafariCollection(
      from: DemoData.safariCapture(referenceDate: referenceDate),
      name: "Safari 阅读"
    )
    let persisted = try #require(repository.loadSnapshots().first)
    let result = try #require(
      SearchEngine.search(
        query: "WebKit",
        liveStates: [],
        snapshots: [persisted]
      ).first
    )

    #expect(persisted == snapshot)
    #expect(result.sourceKind == .safari)
    #expect(result.sourceLabel == SafariCollectionBuilder.sourceLabel)
    #expect(result.kind == .snapshot)
  }
}

@Test
func searchBrowserFilterKeepsChromeAndSafariResultsSeparate() {
  let states = DemoData.liveStates(referenceDate: referenceDate)
  let snapshots = DemoData.snapshots(referenceDate: referenceDate)
  let allResults = SearchEngine.search(
    query: "example.com",
    liveStates: states,
    snapshots: snapshots
  )
  let chromeResults = SearchEngine.search(
    query: "example.com",
    liveStates: states,
    snapshots: snapshots,
    browserFilter: .chrome
  )
  let safariResults = SearchEngine.search(
    query: "example.com",
    liveStates: states,
    snapshots: snapshots,
    browserFilter: .safari
  )

  #expect(Set(allResults.map(\.sourceKind)) == [.chrome, .safari])
  #expect(!chromeResults.isEmpty && chromeResults.allSatisfy { $0.sourceKind == .chrome })
  #expect(!safariResults.isEmpty && safariResults.allSatisfy { $0.sourceKind == .safari })
}

@Test
func browserScopedExportKeepsChromeAndSafariInSeparateFiles() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    for snapshot in DemoData.snapshots(referenceDate: referenceDate) {
      try repository.saveSnapshot(snapshot)
    }

    let chromeURL = paths.root.appendingPathComponent("chrome-library.json")
    let safariURL = paths.root.appendingPathComponent("safari-library.json")
    try repository.exportLibrary(
      to: chromeURL,
      applicationVersion: "test",
      browserKind: .chrome
    )
    try repository.exportLibrary(
      to: safariURL,
      applicationVersion: "test",
      browserKind: .safari
    )

    let decoder = PagecaseJSON.makeDecoder()
    let chromeExport = try decoder.decode(
      LibraryExport.self,
      from: Data(contentsOf: chromeURL)
    )
    let safariExport = try decoder.decode(
      LibraryExport.self,
      from: Data(contentsOf: safariURL)
    )

    #expect(chromeExport.snapshots.count == 4)
    #expect(chromeExport.snapshots.allSatisfy { $0.sourceKind == .chrome })
    #expect(safariExport.snapshots.count == 1)
    #expect(safariExport.snapshots.allSatisfy { $0.sourceKind == .safari })
  }
}

@Test
func snapshotLibraryKeepsChangedGroupContextInAnotherSeries() throws {
  let state = try #require(DemoData.liveStates(referenceDate: referenceDate).first)
  let window = try #require(state.windows.first)
  let group = try #require(window.groups.first)
  let first = SavedSnapshot(
    id: "first-group-version",
    name: "第一个版本",
    createdAt: referenceDate,
    sourceId: state.source.id,
    scope: .group,
    windows: [
      BrowserWindow(
        id: window.id,
        order: window.order,
        focused: window.focused,
        groups: [group],
        ungroupedTabs: []
      )
    ]
  )
  let changedGroup = TabGroup(
    id: group.id,
    title: group.title,
    color: .red,
    collapsed: group.collapsed,
    order: group.order,
    tabs: group.tabs
  )
  let changed = SavedSnapshot(
    id: "changed-group-context",
    name: "颜色变化后的版本",
    createdAt: referenceDate.addingTimeInterval(-60),
    sourceId: state.source.id,
    scope: .group,
    windows: [
      BrowserWindow(
        id: window.id,
        order: window.order,
        focused: window.focused,
        groups: [changedGroup],
        ungroupedTabs: []
      )
    ]
  )
  let renamedGroup = TabGroup(
    id: group.id,
    title: "另一组开发资料",
    color: group.color,
    collapsed: group.collapsed,
    order: group.order,
    tabs: group.tabs
  )
  let renamed = SavedSnapshot(
    id: "renamed-group-context",
    name: "名称变化后的版本",
    createdAt: referenceDate.addingTimeInterval(-120),
    sourceId: state.source.id,
    scope: .group,
    windows: [
      BrowserWindow(
        id: window.id,
        order: window.order,
        focused: window.focused,
        groups: [renamedGroup],
        ungroupedTabs: []
      )
    ]
  )

  let series = SnapshotLibraryOrganizer.organize([first, changed, renamed]).compactMap {
    item -> GroupSnapshotSeries? in
    guard case .groupSeries(let series) = item else {
      return nil
    }
    return series
  }
  #expect(series.count == 3)
  #expect(series.allSatisfy { $0.snapshots.count == 1 })
}

@Test
func snapshotCoveragePreservesContextDuplicatesAndClosedPages() throws {
  let state = try #require(DemoData.liveStates(referenceDate: referenceDate).first)
  let exactSnapshot = SavedSnapshot(
    id: "exact",
    name: "完整快照",
    createdAt: referenceDate.addingTimeInterval(-60),
    sourceId: state.source.id,
    windows: state.windows
  )

  let exactCoverage = SnapshotCoverageEvaluator.evaluate(
    liveState: state,
    snapshots: [exactSnapshot]
  )
  #expect(exactCoverage.isComplete)
  #expect(exactCoverage.coveredPageCount == state.tabCount)

  var reducedWindows = state.windows
  let firstWindow = try #require(reducedWindows.first)
  reducedWindows[0] = BrowserWindow(
    id: firstWindow.id,
    order: firstWindow.order,
    focused: firstWindow.focused,
    groups: firstWindow.groups,
    ungroupedTabs: Array(firstWindow.ungroupedTabs.dropLast())
  )
  let reducedState = LiveState(source: state.source, windows: reducedWindows)
  #expect(
    SnapshotCoverageEvaluator.evaluate(
      liveState: reducedState,
      snapshots: [exactSnapshot]
    ).isComplete
  )

  let incompleteSnapshot = SavedSnapshot(
    id: "incomplete",
    name: "少一个重复网址",
    createdAt: referenceDate,
    sourceId: state.source.id,
    windows: reducedWindows
  )
  let incompleteCoverage = SnapshotCoverageEvaluator.evaluate(
    liveState: state,
    snapshots: [incompleteSnapshot]
  )
  #expect(incompleteCoverage.uncoveredPageCount == 1)

  var changedContextWindows = state.windows
  var changedGroups = firstWindow.groups
  let firstGroup = try #require(changedGroups.first)
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
    id: "changed-context",
    name: "标签组不同",
    sourceId: state.source.id,
    windows: changedContextWindows
  )
  #expect(
    SnapshotCoverageEvaluator.evaluate(
      liveState: state,
      snapshots: [changedContextSnapshot]
    ).uncoveredPageCount == firstGroup.tabs.count
  )

  let bestCoverage = SnapshotCoverageEvaluator.evaluate(
    liveState: state,
    snapshots: [incompleteSnapshot, exactSnapshot]
  )
  #expect(bestCoverage.snapshot?.id == exactSnapshot.id)

  let wrongSourceSnapshot = SavedSnapshot(
    id: "wrong-source",
    name: "其他来源",
    sourceId: "other-source",
    windows: state.windows
  )
  let missingCoverage = SnapshotCoverageEvaluator.evaluate(
    liveState: state,
    snapshots: [wrongSourceSnapshot]
  )
  #expect(missingCoverage.snapshot == nil)
  #expect(missingCoverage.uncoveredPageCount == state.tabCount)

  let safariImpostor = SavedSnapshot(
    id: "safari-impostor",
    name: "不应覆盖 Chrome",
    sourceId: state.source.id,
    sourceKind: .safari,
    sourceLabel: "Safari",
    windows: state.windows
  )
  #expect(
    SnapshotCoverageEvaluator.evaluate(
      liveState: state,
      snapshots: [safariImpostor]
    ).snapshot == nil
  )
}

@Test
func groupCoveragePreservesDuplicateURLsAndDoesNotMergeGroups() {
  let liveGroup = TabGroup(
    id: 10,
    title: "研究",
    color: .blue,
    collapsed: false,
    order: 0,
    tabs: [
      PageItem(
        id: 1,
        windowId: 1,
        groupId: 10,
        index: 0,
        title: "重复一",
        url: "https://example.com/shared"
      ),
      PageItem(
        id: 2,
        windowId: 1,
        groupId: 10,
        index: 1,
        title: "重复二",
        url: "https://example.com/shared"
      )
    ]
  )
  let firstSavedGroup = TabGroup(
    id: 20,
    title: "研究",
    color: .blue,
    collapsed: false,
    order: 0,
    tabs: [
      PageItem(
        id: 3,
        windowId: 2,
        groupId: 20,
        index: 0,
        title: "只保存一份",
        url: "https://example.com/shared"
      )
    ]
  )
  let secondSavedGroup = TabGroup(
    id: 21,
    title: "研究",
    color: .blue,
    collapsed: false,
    order: 1,
    tabs: [
      PageItem(
        id: 4,
        windowId: 2,
        groupId: 21,
        index: 1,
        title: "另一组的一份",
        url: "https://example.com/shared"
      )
    ]
  )
  let splitSnapshot = SavedSnapshot(
    id: "split-groups",
    name: "同名组不可合并",
    sourceId: "source",
    windows: [
      BrowserWindow(
        id: 2,
        order: 0,
        focused: false,
        groups: [firstSavedGroup, secondSavedGroup],
        ungroupedTabs: []
      )
    ]
  )

  let splitCoverage = SnapshotCoverageEvaluator.evaluate(
    group: liveGroup,
    sourceId: "source",
    snapshots: [splitSnapshot]
  )
  #expect(splitCoverage.uncoveredPageCount == 1)
  #expect(!splitCoverage.isComplete)

  let exactSnapshot = SavedSnapshot(
    id: "exact-group",
    name: "完整分组",
    sourceId: "source",
    windows: [
      BrowserWindow(
        id: 1,
        order: 0,
        focused: true,
        groups: [liveGroup],
        ungroupedTabs: []
      )
    ]
  )
  #expect(
    SnapshotCoverageEvaluator.evaluate(
      group: liveGroup,
      sourceId: "source",
      snapshots: [splitSnapshot, exactSnapshot]
    ).isComplete
  )
  let exactCoverage = SnapshotCoverageEvaluator.evaluate(
    group: liveGroup,
    sourceId: "source",
    snapshots: [exactSnapshot]
  )
  #expect(exactCoverage.windowId == 1)
  #expect(exactCoverage.groupId == liveGroup.id)
  #expect(
    SnapshotCoverageEvaluator.evaluate(
      group: liveGroup,
      sourceId: "other-source",
      snapshots: [exactSnapshot]
    ).snapshot == nil
  )
}

@Test
func searchMatchesTitleGroupDomainURLAndSnapshotName() {
  let states = DemoData.liveStates(referenceDate: referenceDate)
  let snapshots = DemoData.snapshots(referenceDate: referenceDate)

  #expect(
    SearchEngine.search(query: "Prisma", liveStates: states, snapshots: []).first?.title
      == "Prisma ORM 文档"
  )
  #expect(!SearchEngine.search(query: "AI 工具", liveStates: states, snapshots: []).isEmpty)
  #expect(!SearchEngine.search(query: "github.com", liveStates: states, snapshots: []).isEmpty)
  #expect(!SearchEngine.search(query: "localhost:3000", liveStates: states, snapshots: []).isEmpty)

  let snapshotMatches = SearchEngine.search(
    query: "七月的工具",
    liveStates: [],
    snapshots: snapshots
  )
  #expect(!snapshotMatches.isEmpty)
  #expect(snapshotMatches.allSatisfy { $0.kind == .snapshot })
}

@Test
func searchReturnsGroupsBeforeTheirPagesWithNavigationMetadata() throws {
  let states = DemoData.liveStates(referenceDate: referenceDate)
  let snapshots = DemoData.snapshots(referenceDate: referenceDate)
  let results = SearchEngine.search(
    query: "AI 工具",
    liveStates: states,
    snapshots: snapshots
  )
  let first = try #require(results.first)

  #expect(first.target == .group)
  #expect(first.kind == .live)
  #expect(first.title == "AI 工具")
  #expect(first.windowId != nil)
  #expect(first.groupId != nil)
  #expect(first.pageCount == 3)
  #expect(results.contains { $0.target == .page })

  let snapshotGroup = try #require(
    results.first { $0.target == .group && $0.kind == .snapshot }
  )
  #expect(snapshotGroup.snapshotId != nil)
  #expect(snapshotGroup.windowId != nil)
  #expect(snapshotGroup.groupId != nil)
  #expect(snapshotGroup.url == nil)
}

@Test
func searchPreservesDuplicateURLsAndUsesUniqueResultIds() {
  let states = DemoData.liveStates(referenceDate: referenceDate)
  let snapshots = DemoData.snapshots(referenceDate: referenceDate)
  let results = SearchEngine.search(
    query: "shared-context",
    liveStates: states,
    snapshots: snapshots
  )

  #expect(results.count > 2)
  #expect(Set(results.map(\.id)).count == results.count)
}

@Test
func pageUsesDomainWhenTitleIsEmpty() {
  let page = PageItem(
    id: 1,
    windowId: 2,
    groupId: nil,
    index: 0,
    title: "  ",
    url: "https://www.example.com/path"
  )

  #expect(page.displayTitle == "example.com")
  #expect(page.domain == "example.com")
}

@Test
func liveStateAndSnapshotRemainIndependent() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    let firstState = try #require(DemoData.liveStates().first)

    try repository.saveLiveState(firstState)
    let snapshot = try repository.createSnapshot(from: firstState, name: "开发现场")

    let replacement = DemoData.performanceState(tabCount: 3)
    try repository.saveLiveState(replacement)

    let savedSnapshot = try #require(repository.loadSnapshots().first)
    #expect(savedSnapshot.id == snapshot.id)
    #expect(savedSnapshot.tabCount == firstState.tabCount)
    #expect(savedSnapshot.tabCount != replacement.tabCount)
  }
}

@Test
func legacySnapshotWithoutScopeDefaultsToFullState() throws {
  let state = try #require(DemoData.liveStates(referenceDate: referenceDate).first)
  let snapshot = SavedSnapshot(
    id: "legacy-snapshot",
    name: "旧版完整现场",
    createdAt: referenceDate,
    sourceId: state.source.id,
    windows: state.windows
  )
  let encoded = try PagecaseJSON.makeEncoder().encode(snapshot)
  var object = try #require(
    JSONSerialization.jsonObject(with: encoded) as? [String: Any]
  )
  object.removeValue(forKey: "scope")
  object.removeValue(forKey: "sourceKind")
  object.removeValue(forKey: "sourceLabel")
  let legacyData = try JSONSerialization.data(withJSONObject: object)

  let decoded = try PagecaseJSON.makeDecoder().decode(
    SavedSnapshot.self,
    from: legacyData
  )

  #expect(decoded.scope == .fullState)
  #expect(decoded.sourceKind == .chrome)
  #expect(decoded.sourceLabel == "Chrome")
  #expect(decoded.windows == snapshot.windows)
}

@Test
func safariCollectionRejectsChromeOrGroupedContent() throws {
  let chromeCollection = SavedSnapshot(
    id: "invalid-chrome-collection",
    name: "错误合集",
    sourceId: "chrome-source",
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

  #expect(throws: StoreError.self) {
    try PagecaseValidator.validate(chromeCollection)
  }
}

@Test
func groupSnapshotPersistsOnlyTheSelectedGroup() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    let state = try #require(DemoData.liveStates(referenceDate: referenceDate).first)
    let window = try #require(state.windows.first)
    let group = try #require(window.groups.first)

    let snapshot = try repository.createGroupSnapshot(
      from: group,
      in: window,
      sourceId: state.source.id,
      name: "  开发资料  ",
      now: referenceDate
    )
    let persisted = try #require(repository.loadSnapshots().first)

    #expect(snapshot.name == "开发资料")
    #expect(snapshot.scope == .group)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].groups == [group])
    #expect(snapshot.windows[0].ungroupedTabs.isEmpty)
    #expect(persisted == snapshot)

    let coverage = SnapshotCoverageEvaluator.evaluate(
      group: group,
      sourceId: state.source.id,
      snapshots: [persisted]
    )
    #expect(coverage.isComplete)
    #expect(coverage.windowId == window.id)
    #expect(coverage.groupId == group.id)

    let fullStateCoverage = SnapshotCoverageEvaluator.evaluate(
      liveState: state,
      snapshots: [persisted]
    )
    #expect(fullStateCoverage.snapshot == nil)
    #expect(fullStateCoverage.uncoveredPageCount == state.tabCount)

    let exportURL = paths.root.appendingPathComponent("group-library.json")
    try repository.exportLibrary(to: exportURL, applicationVersion: "test")
    let imported = try repository.importLibrary(from: exportURL)
    #expect(imported.first?.id != snapshot.id)
    #expect(imported.first?.scope == .group)
    #expect(try repository.loadSnapshots().count == 2)
  }
}

@Test
func groupSnapshotRejectsMoreThanOneGroup() throws {
  let state = try #require(DemoData.liveStates(referenceDate: referenceDate).first)
  let invalid = SavedSnapshot(
    id: "invalid-group-snapshot",
    name: "不合法的标签组快照",
    sourceId: state.source.id,
    scope: .group,
    windows: state.windows
  )

  #expect(throws: StoreError.self) {
    try PagecaseValidator.validate(invalid)
  }
}

@Test
func deleteSnapshotRemovesOnlyTheSelectedSnapshot() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    let state = try #require(DemoData.liveStates().first)

    try repository.saveLiveState(state)
    let deleted = try repository.createSnapshot(from: state, name: "准备删除")
    let retained = try repository.createSnapshot(from: state, name: "继续保留")

    try repository.deleteSnapshot(id: deleted.id)

    let snapshots = try repository.loadSnapshots()
    #expect(snapshots.map(\.id) == [retained.id])
    #expect(try repository.loadLiveStates().first?.source.id == state.source.id)
  }
}

@Test
func displayPreferencesPersistCollapsedGroups() throws {
  try withTemporaryPaths { paths in
    let repository = DisplayPreferencesRepository(paths: paths)
    let key = DisplayPreferences.groupKey(
      scope: "live:source",
      windowId: 20,
      groupId: 30
    )
    let preferences = DisplayPreferences(collapsedGroupKeys: [key])

    try repository.save(preferences)

    #expect(try repository.load() == preferences)
    #expect(
      DisplayPreferences.groupKey(
        scope: "snapshot:saved",
        windowId: 20,
        groupId: nil
      ) == "snapshot:saved:window:20:group:ungrouped"
    )
  }
}

@Test
func exportImportRoundTripAndIdConflict() throws {
  try withTemporaryPaths { sourcePaths in
    let sourceRepository = try SnapshotRepository(paths: sourcePaths)
    let state = try #require(DemoData.liveStates().first)
    let original = try sourceRepository.createSnapshot(from: state, name: "待导出")
    let exportURL = sourcePaths.root.appendingPathComponent("library.json")
    try sourceRepository.exportLibrary(to: exportURL, applicationVersion: "test")

    try withTemporaryPaths { destinationPaths in
      let destinationRepository = try SnapshotRepository(paths: destinationPaths)
      let firstImport = try destinationRepository.importLibrary(from: exportURL)
      let secondImport = try destinationRepository.importLibrary(from: exportURL)

      #expect(firstImport.first?.id == original.id)
      #expect(secondImport.first?.id != original.id)
      #expect(try destinationRepository.loadSnapshots().count == 2)
    }
  }
}

@Test
func invalidImportDoesNotPartiallyChangeLibrary() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    let state = try #require(DemoData.liveStates().first)
    let existing = try repository.createSnapshot(from: state, name: "原有快照")

    let valid = SavedSnapshot(
      id: "valid-import",
      name: "有效快照",
      sourceId: state.source.id,
      windows: state.windows
    )
    let invalidPage = PageItem(
      id: 99_001,
      windowId: 99_000,
      groupId: nil,
      index: 0,
      title: "不应导入",
      url: "file:///tmp/private"
    )
    let invalid = SavedSnapshot(
      id: "invalid-import",
      name: "损坏快照",
      sourceId: state.source.id,
      windows: [
        BrowserWindow(
          id: 99_000,
          order: 0,
          focused: false,
          groups: [],
          ungroupedTabs: [invalidPage]
        )
      ]
    )
    let importURL = paths.root.appendingPathComponent("invalid-library.json")
    try AtomicJSONStore().write(
      LibraryExport(applicationVersion: "test", snapshots: [valid, invalid]),
      to: importURL
    )

    do {
      try repository.importLibrary(from: importURL)
      Issue.record("包含损坏快照的资料库应整体拒绝")
    } catch {
      #expect(error is StoreError)
    }

    let remaining = try repository.loadSnapshots()
    #expect(remaining.count == 1)
    #expect(remaining.first?.id == existing.id)
  }
}

@Test
func liveStateValidationRejectsInconsistentPageContext() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    let page = PageItem(
      id: 2,
      windowId: 99,
      groupId: nil,
      index: 0,
      title: "窗口不一致",
      url: "https://example.com"
    )
    let state = LiveState(
      source: BrowserSource(id: "source", label: "Chrome", capturedAt: referenceDate),
      windows: [
        BrowserWindow(
          id: 1,
          order: 0,
          focused: true,
          groups: [],
          ungroupedTabs: [page]
        )
      ]
    )

    do {
      try repository.saveLiveState(state)
      Issue.record("窗口标识不一致的网页应被拒绝")
    } catch {
      #expect(error is StoreError)
    }
    #expect(try repository.loadLiveStates().isEmpty)
  }
}

@Test
func nativeHostManagerInstallsInspectsAndRemovesExactManifest() throws {
  try withTemporaryPaths { paths in
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

    #expect(manager.inspect().state == .missing)
    let installed = try manager.install(extensionId: extensionId)
    #expect(installed.state == .ready)
    #expect(installed.extensionId == extensionId)

    let attributes = try FileManager.default.attributesOfItem(
      atPath: manager.manifestURL.path
    )
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o644)

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
    #expect(movedManager.inspect().state == .invalid)

    try manager.uninstall()
    #expect(manager.inspect().state == .missing)
    #expect(!FileManager.default.fileExists(atPath: manager.manifestURL.path))
  }
}

@Test
func nativeHostManagerRejectsInvalidExtensionIdAndManifest() throws {
  try withTemporaryPaths { paths in
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

    do {
      try manager.install(extensionId: "not-a-chrome-extension-id")
      Issue.record("无效扩展标识应被拒绝")
    } catch {
      #expect(error is StoreError)
    }
    #expect(manager.inspect().state == .missing)

    try FileManager.default.createDirectory(
      at: manager.manifestDirectory,
      withIntermediateDirectories: true
    )
    try Data("{}".utf8).write(to: manager.manifestURL)
    #expect(manager.inspect().state == .invalid)
  }
}

@Test
func extensionPackageManagerPreparesCompleteVerifiedDirectory() throws {
  try withTemporaryPaths { paths in
    try paths.createDirectories()
    let source = paths.root.appendingPathComponent("BundledExtension", isDirectory: true)
    let destination = paths.root.appendingPathComponent("ChromeExtension", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("stale".utf8).write(to: destination.appendingPathComponent("stale.txt"))

    for file in ExtensionPackageManager.requiredFiles {
      try Data("content:\(file)".utf8).write(to: source.appendingPathComponent(file))
    }

    let manager = ExtensionPackageManager(
      sourceDirectory: source,
      destinationDirectory: destination
    )
    #expect(manager.isSourceAvailable())
    #expect(try manager.prepare() == destination)
    #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("stale.txt").path))

    for file in ExtensionPackageManager.requiredFiles {
      #expect(
        try Data(contentsOf: source.appendingPathComponent(file))
          == Data(contentsOf: destination.appendingPathComponent(file))
      )
    }
  }
}

@Test
func extensionPackageManagerRejectsIncompleteSourceWithoutChangingDestination() throws {
  try withTemporaryPaths { paths in
    try paths.createDirectories()
    let source = paths.root.appendingPathComponent("IncompleteExtension", isDirectory: true)
    let destination = paths.root.appendingPathComponent("ChromeExtension", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let existing = destination.appendingPathComponent("existing.txt")
    try Data("keep".utf8).write(to: existing)

    let manager = ExtensionPackageManager(
      sourceDirectory: source,
      destinationDirectory: destination
    )
    do {
      try manager.prepare()
      Issue.record("不完整的扩展来源应被拒绝")
    } catch {
      #expect(error is StoreError)
    }
    #expect(try Data(contentsOf: existing) == Data("keep".utf8))
  }
}

@Test
func invalidSchemaIsRejected() throws {
  try withTemporaryPaths { paths in
    let repository = try SnapshotRepository(paths: paths)
    let invalid = SavedSnapshot(
      schemaVersion: 99,
      name: "未知版本",
      sourceId: "source",
      windows: []
    )

    do {
      try repository.saveSnapshot(invalid)
      Issue.record("未知 schema 应被拒绝")
    } catch {
      #expect(error as? StoreError == .unsupportedSchema(99))
    }
  }
}

@Test
func failedEncodingKeepsExistingFile() throws {
  struct FailingValue: Encodable {
    enum Failure: Error {
      case expected
    }

    func encode(to encoder: Encoder) throws {
      throw Failure.expected
    }
  }

  try withTemporaryPaths { paths in
    try paths.createDirectories()
    let file = paths.root.appendingPathComponent("atomic.json")
    let original = Data("{\"safe\":true}".utf8)
    try original.write(to: file)

    do {
      try AtomicJSONStore().write(FailingValue(), to: file)
      Issue.record("编码失败应向上传递")
    } catch {
      #expect(try Data(contentsOf: file) == original)
    }
  }
}

@Test
func commandValidationAllowsOnlyExpectedShapes() throws {
  try BrowserCommand(
    sourceId: "source",
    action: .focusTab,
    tabId: 1,
    windowId: 2
  ).validate()
  try BrowserCommand(
    sourceId: "source",
    action: .openUrl,
    url: "https://example.com"
  ).validate()
  try BrowserCommand(
    sourceId: "source",
    action: .restoreGroup,
    groupTitle: "开发",
    groupColor: .blue,
    urls: [
      "https://example.com/first",
      "https://example.com/second"
    ]
  ).validate()

  do {
    try BrowserCommand(
      sourceId: "source",
      action: .openUrl,
      url: "file:///tmp/private"
    ).validate()
    Issue.record("非 Web 协议应被拒绝")
  } catch {
    #expect(error is StoreError)
  }

  do {
    try BrowserCommand(
      sourceId: "source",
      action: .restoreGroup,
      groupTitle: "无效",
      groupColor: .blue,
      urls: ["file:///tmp/private"]
    ).validate()
    Issue.record("恢复整组中的非 Web 协议应被拒绝")
  } catch {
    #expect(error is StoreError)
  }
}

@Test
func commandLifecycle() throws {
  try withTemporaryPaths { paths in
    let repository = try CommandRepository(paths: paths)
    let command = BrowserCommand(
      sourceId: "source",
      action: .focusTab,
      tabId: 10,
      windowId: 20
    )

    try repository.enqueue(command)
    let pending = try repository.loadPendingCommands()
    #expect(pending.count == 1)
    #expect(pending.first?.id == command.id)

    try repository.claim(command)
    #expect(try repository.loadPendingCommands().isEmpty)
    let processing = try repository.loadProcessingCommands()
    #expect(processing.count == 1)
    #expect(processing.first?.id == command.id)

    let result = BrowserCommandResult(
      id: command.id,
      sourceId: command.sourceId,
      success: true,
      message: "已定位"
    )
    try repository.saveResult(result)

    #expect(try repository.loadProcessingCommands().isEmpty)
    let savedResult = try repository.loadResult(commandId: command.id)
    #expect(savedResult?.id == result.id)
    #expect(savedResult?.success == result.success)
  }
}

@Test
func nativeMessageRoundTripAndLengthValidation() throws {
  let message = NativeOutboundMessage(type: "pong")
  let framed = try NativeMessageFramer.encode(message)
  let decoded = try NativeMessageFramer.decode(NativeOutboundMessage.self, from: framed)

  #expect(decoded.type == "pong")

  let restoreMessage = NativeOutboundMessage(
    command: BrowserCommand(
      sourceId: "source",
      action: .restoreGroup,
      groupTitle: "开发",
      groupColor: .blue,
      urls: ["https://example.com"]
    )
  )
  let restoreFramed = try NativeMessageFramer.encode(restoreMessage)
  let restoreDecoded = try NativeMessageFramer.decode(
    NativeOutboundMessage.self,
    from: restoreFramed
  )
  #expect(restoreDecoded.type == "restoreGroup")
  #expect(restoreDecoded.groupTitle == "开发")
  #expect(restoreDecoded.groupColor == "blue")
  #expect(restoreDecoded.urls == ["https://example.com"])

  var invalid = framed
  invalid.removeLast()
  do {
    _ = try NativeMessageFramer.decode(NativeOutboundMessage.self, from: invalid)
    Issue.record("长度不一致的消息应被拒绝")
  } catch {
    #expect(error is StoreError)
  }
}

@Test
func nativeMessageRejectsPayloadLargerThanLimit() {
  struct LargePayload: Encodable {
    let value = String(repeating: "a", count: PagecaseSchema.nativeMessageLimit + 1)
  }

  do {
    _ = try NativeMessageFramer.encode(LargePayload())
    Issue.record("超过 4MB 的消息应被拒绝")
  } catch {
    if case StoreError.messageTooLarge = error {
      return
    }
    Issue.record("应返回 messageTooLarge")
  }
}

private func withTemporaryPaths<T>(_ operation: (AppPaths) throws -> T) throws -> T {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("PagecaseTests-\(UUID().uuidString)", isDirectory: true)
  defer {
    if FileManager.default.fileExists(atPath: root.path) {
      try? FileManager.default.removeItem(at: root)
    }
  }
  return try operation(AppPaths(root: root))
}
