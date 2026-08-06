import Foundation
@testable import PagecaseCore
import Testing

private let referenceDate = Date(timeIntervalSince1970: 1_754_486_400)

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
