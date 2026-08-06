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

  let duplicateResults = SearchEngine.search(
    query: "shared-context",
    liveStates: states,
    snapshots: snapshots
  )
  passed += try check(
    Set(duplicateResults.map(\.id)).count == duplicateResults.count,
    "搜索结果标识发生冲突"
  )

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

    return localPassed
  }

  let framed = try NativeMessageFramer.encode(NativeOutboundMessage(type: "pong"))
  let decoded = try NativeMessageFramer.decode(NativeOutboundMessage.self, from: framed)
  passed += try check(decoded.type == "pong", "Native Messaging 往返失败")

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

  return passed
}

do {
  let passed = try runChecks()
  print("PagecaseCoreChecks: \(passed) 项检查通过")
} catch {
  FileHandle.standardError.write(Data("PagecaseCoreChecks: \(error.localizedDescription)\n".utf8))
  exit(EXIT_FAILURE)
}
