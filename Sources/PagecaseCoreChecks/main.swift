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

  let snapshots = DemoData.snapshots(referenceDate: referenceDate)
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
  let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
  let legacySnapshot = try PagecaseJSON.makeDecoder().decode(
    SavedSnapshot.self,
    from: legacyData
  )
  passed += try check(
    legacySnapshot.scope == .fullState,
    "旧快照未默认识别为完整现场"
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
