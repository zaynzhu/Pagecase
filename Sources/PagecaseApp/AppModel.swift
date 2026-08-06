import AppKit
import Foundation
import PagecaseCore

enum NavigationItem: String, CaseIterable, Identifiable {
  case live
  case snapshots
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .live:
      return "现在"
    case .snapshots:
      return "快照"
    case .settings:
      return "设置"
    }
  }

  var symbol: String {
    switch self {
    case .live:
      return "rectangle.stack"
    case .snapshots:
      return "archivebox"
    case .settings:
      return "gearshape"
    }
  }
}

struct AppNotice: Identifiable, Equatable {
  enum Kind {
    case success
    case warning
    case error
  }

  let id = UUID()
  let kind: Kind
  let message: String
}

enum SourceAvailability: Equatable {
  case connected
  case stale
  case missing
}

@MainActor
final class AppModel: ObservableObject {
  static let applicationVersion = "0.1.0"

  @Published var selection: NavigationItem = .live
  @Published var liveStates: [LiveState] = []
  @Published var snapshots: [SavedSnapshot] = []
  @Published var selectedSourceId: String?
  @Published var selectedSnapshotId: String?
  @Published var searchQuery = ""
  @Published var selectedSearchResultId: String?
  @Published var searchFocusRequest = 0
  @Published var extensionId = ""
  @Published var nativeHostStatus: NativeHostStatus
  @Published private(set) var sourceAvailabilityById: [String: SourceAvailability] = [:]
  @Published var notice: AppNotice?

  let paths: AppPaths
  let isDemoMode: Bool
  let isPerformanceMode: Bool
  let bundledExtensionDirectory: URL
  let preparedExtensionDirectory: URL

  private let snapshotRepository: SnapshotRepository?
  private let commandRepository: CommandRepository?
  private let nativeHostManager: NativeHostManager
  private let extensionPackageManager: ExtensionPackageManager
  private var pendingCommands: [String: Date] = [:]
  private var contentSignature: String?
  private var handledSearchFocusRequest = 0

  static func make() -> AppModel {
    let environment = ProcessInfo.processInfo.environment
    let fallback = AppPaths(
      root: FileManager.default.temporaryDirectory
        .appendingPathComponent("Pagecase-Fallback", isDirectory: true)
    )
    let paths = (try? AppPaths.defaultPaths(environment: environment)) ?? fallback
    let isPerformanceMode = environment["PAGECASE_PERFORMANCE"] == "1"
      || ProcessInfo.processInfo.arguments.contains("--performance")
    let isDemoMode = environment["PAGECASE_DEMO"] == "1"
      || ProcessInfo.processInfo.arguments.contains("--demo")
      || isPerformanceMode
    let nativeHostDirectory: URL
    if let override = environment["PAGECASE_NATIVE_HOST_ROOT"], !override.isEmpty {
      nativeHostDirectory = URL(fileURLWithPath: override, isDirectory: true)
    } else if isDemoMode {
      nativeHostDirectory = paths.root.appendingPathComponent("DemoNativeMessagingHosts", isDirectory: true)
    } else {
      nativeHostDirectory = (try? NativeHostManager.defaultManifestDirectory(environment: environment))
        ?? paths.root.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }
    let bundleURL = Bundle.main.bundleURL
    let bridgeURL = environment["PAGECASE_BRIDGE_PATH"].map {
      URL(fileURLWithPath: $0)
    } ?? bundleURL.appendingPathComponent("Contents/MacOS/PagecaseBridge")
    let extensionDirectory = environment["PAGECASE_EXTENSION_ROOT"].map {
      URL(fileURLWithPath: $0, isDirectory: true)
    } ?? bundleURL.appendingPathComponent("Contents/Resources/ChromeExtension", isDirectory: true)

    return AppModel(
      paths: paths,
      isDemoMode: isDemoMode,
      isPerformanceMode: isPerformanceMode,
      nativeHostDirectory: nativeHostDirectory,
      bridgeURL: bridgeURL,
      extensionDirectory: extensionDirectory
    )
  }

  init(
    paths: AppPaths,
    isDemoMode: Bool,
    isPerformanceMode: Bool = false,
    nativeHostDirectory: URL? = nil,
    bridgeURL: URL? = nil,
    extensionDirectory: URL? = nil
  ) {
    self.paths = paths
    self.isDemoMode = isDemoMode
    self.isPerformanceMode = isPerformanceMode
    let resolvedBridgeURL = bridgeURL
      ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/PagecaseBridge")
    let manager = NativeHostManager(
      manifestDirectory: nativeHostDirectory
        ?? paths.root.appendingPathComponent("NativeMessagingHosts", isDirectory: true),
      bridgeURL: resolvedBridgeURL
    )
    nativeHostManager = manager
    let initialNativeHostStatus = manager.inspect()
    nativeHostStatus = initialNativeHostStatus
    bundledExtensionDirectory = extensionDirectory
      ?? Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Resources/ChromeExtension",
        isDirectory: true
      )
    preparedExtensionDirectory = paths.root.appendingPathComponent(
      "ChromeExtension",
      isDirectory: true
    )
    extensionPackageManager = ExtensionPackageManager(
      sourceDirectory: bundledExtensionDirectory,
      destinationDirectory: preparedExtensionDirectory
    )
    self.extensionId = initialNativeHostStatus.extensionId ?? ""

    let repositories: (SnapshotRepository?, CommandRepository?, Error?)
    do {
      repositories = (
        try SnapshotRepository(paths: paths),
        try CommandRepository(paths: paths),
        nil
      )
    } catch {
      repositories = (nil, nil, error)
    }
    snapshotRepository = repositories.0
    commandRepository = repositories.1
    if let error = repositories.2 {
      notice = AppNotice(kind: .error, message: error.localizedDescription)
    }

    if isDemoMode {
      do {
        try DemoData.seedIfNeeded(paths: paths, performance: isPerformanceMode)
      } catch {
        notice = AppNotice(kind: .error, message: "演示数据准备失败：\(error.localizedDescription)")
      }
    }

    refresh()
  }

  var selectedLiveState: LiveState? {
    if let selectedSourceId,
       let selected = liveStates.first(where: { $0.source.id == selectedSourceId }) {
      return selected
    }
    return liveStates.first
  }

  var selectedSnapshot: SavedSnapshot? {
    if let selectedSnapshotId,
       let selected = snapshots.first(where: { $0.id == selectedSnapshotId }) {
      return selected
    }
    return snapshots.first
  }

  var searchResults: [SearchResult] {
    SearchEngine.search(
      query: searchQuery,
      liveStates: liveStates,
      snapshots: snapshots,
      sourceLabels: Dictionary(uniqueKeysWithValues: liveStates.map { ($0.source.id, $0.source.label) })
    )
  }

  var selectedSearchResult: SearchResult? {
    let results = searchResults
    if let selectedSearchResultId,
       let selected = results.first(where: { $0.id == selectedSearchResultId }) {
      return selected
    }
    return results.first
  }

  var totalLiveTabs: Int {
    liveStates.reduce(0) { $0 + $1.tabCount }
  }

  var hasConnectedSource: Bool {
    sourceAvailabilityById.values.contains(.connected)
  }

  var connectedSourceCount: Int {
    sourceAvailabilityById.values.filter { $0 == .connected }.count
  }

  var staleSourceCount: Int {
    sourceAvailabilityById.values.filter { $0 == .stale }.count
  }

  var extensionPackageAvailable: Bool {
    extensionPackageManager.isSourceAvailable()
  }

  var canConfigureNativeHost: Bool {
    NativeHostManager.isValidExtensionId(
      extensionId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    )
  }

  func isSourceConnected(_ sourceId: String, now: Date = Date()) -> Bool {
    guard let state = liveStates.first(where: { $0.source.id == sourceId }) else {
      return false
    }
    return state.source.isFresh(at: now)
  }

  func sourceAvailability(for sourceId: String) -> SourceAvailability {
    sourceAvailabilityById[sourceId] ?? .missing
  }

  func isSourceActionAvailable(_ sourceId: String) -> Bool {
    isDemoMode || sourceAvailability(for: sourceId) == .connected
  }

  func liveActionTitle(for sourceId: String) -> String {
    isSourceActionAvailable(sourceId) ? "定位" : "数据已过期"
  }

  func snapshotActionTitle(for sourceId: String) -> String {
    isSourceActionAvailable(sourceId) ? "打开" : "Chrome 未连接"
  }

  func isSearchActionAvailable(_ result: SearchResult) -> Bool {
    isSourceActionAvailable(result.sourceId)
  }

  func searchActionTitle(for result: SearchResult) -> String {
    switch result.kind {
    case .live:
      return liveActionTitle(for: result.sourceId)
    case .snapshot:
      return snapshotActionTitle(for: result.sourceId)
    }
  }

  func requestSearchFocus() {
    searchFocusRequest += 1
  }

  func consumeSearchFocusRequest() -> Bool {
    guard handledSearchFocusRequest != searchFocusRequest else {
      return false
    }
    handledSearchFocusRequest = searchFocusRequest
    return true
  }

  func refresh(force: Bool = false) {
    let currentNativeHostStatus = nativeHostManager.inspect()
    if currentNativeHostStatus != nativeHostStatus {
      nativeHostStatus = currentNativeHostStatus
    }
    guard let snapshotRepository else {
      return
    }

    do {
      let signature = try localContentSignature()
      if !force, signature == contentSignature {
        refreshSourceAvailability()
        checkCommandResults()
        return
      }

      liveStates = try snapshotRepository.loadLiveStates()
      snapshots = try snapshotRepository.loadSnapshots()
      contentSignature = signature
      refreshSourceAvailability()

      if selectedSourceId == nil || !liveStates.contains(where: { $0.source.id == selectedSourceId }) {
        selectedSourceId = liveStates.first?.source.id
      }
      if selectedSnapshotId == nil || !snapshots.contains(where: { $0.id == selectedSnapshotId }) {
        selectedSnapshotId = snapshots.first?.id
      }
      reconcileSearchSelection()

      checkCommandResults()
    } catch {
      notice = AppNotice(kind: .error, message: "读取本地资料失败：\(error.localizedDescription)")
    }
  }

  func createSnapshot(name: String) -> Bool {
    guard let state = selectedLiveState, let snapshotRepository else {
      notice = AppNotice(kind: .warning, message: "当前没有可以保存的 Chrome 现场")
      return false
    }

    do {
      let snapshot = try snapshotRepository.createSnapshot(from: state, name: name)
      selectedSnapshotId = snapshot.id
      refresh(force: true)
      notice = AppNotice(
        kind: .success,
        message: "已从磁盘核对保存 \(snapshot.tabCount) 个网页、\(snapshot.groupCount) 个标签组，Chrome 保持不变"
      )
      return true
    } catch {
      notice = AppNotice(kind: .error, message: error.localizedDescription)
      return false
    }
  }

  func renameSnapshot(_ snapshot: SavedSnapshot, name: String) -> Bool {
    guard let snapshotRepository else {
      return false
    }

    do {
      let updated = try snapshotRepository.renameSnapshot(snapshot, to: name)
      selectedSnapshotId = updated.id
      refresh(force: true)
      notice = AppNotice(kind: .success, message: "快照已重命名")
      return true
    } catch {
      notice = AppNotice(kind: .error, message: error.localizedDescription)
      return false
    }
  }

  func deleteSnapshot(_ snapshot: SavedSnapshot) {
    guard let snapshotRepository else {
      return
    }

    do {
      try snapshotRepository.deleteSnapshot(id: snapshot.id)
      refresh(force: true)
      notice = AppNotice(kind: .success, message: "快照已删除")
    } catch {
      notice = AppNotice(kind: .error, message: "删除失败：\(error.localizedDescription)")
    }
  }

  func activate(_ result: SearchResult) {
    switch result.kind {
    case .live:
      guard let tabId = result.tabId, let windowId = result.windowId else {
        notice = AppNotice(kind: .error, message: "定位信息不完整")
        return
      }
      enqueue(
        BrowserCommand(
          sourceId: result.sourceId,
          action: .focusTab,
          tabId: tabId,
          windowId: windowId
        ),
        demoMessage: "演示模式不会定位真实 Chrome 标签"
      )
    case .snapshot:
      enqueue(
        BrowserCommand(
          sourceId: result.sourceId,
          action: .openUrl,
          url: result.url
        ),
        demoMessage: "演示模式不会在 Chrome 中打开网页"
      )
    }
  }

  func activateSelectedSearchResult() {
    guard let result = selectedSearchResult else {
      return
    }
    guard isSearchActionAvailable(result) else {
      notice = AppNotice(
        kind: .warning,
        message: result.kind == .live
          ? "实时数据已经过期，等待 Chrome 重新连接后才能定位"
          : "Chrome 未连接，暂时无法打开这个快照网页"
      )
      return
    }
    activate(result)
  }

  func selectSearchResult(_ result: SearchResult) {
    selectedSearchResultId = result.id
  }

  func resetSearchSelection() {
    selectedSearchResultId = searchResults.first?.id
  }

  func moveSearchSelection(by offset: Int) {
    let results = searchResults
    guard !results.isEmpty else {
      selectedSearchResultId = nil
      return
    }

    guard let selectedSearchResultId,
          let currentIndex = results.firstIndex(where: { $0.id == selectedSearchResultId }) else {
      self.selectedSearchResultId = offset < 0 ? results.last?.id : results.first?.id
      return
    }

    let destination = min(max(currentIndex + offset, 0), results.count - 1)
    self.selectedSearchResultId = results[destination].id
  }

  func clearSearch() {
    searchQuery = ""
    selectedSearchResultId = nil
  }

  func focus(page: PageItem, sourceId: String) {
    enqueue(
      BrowserCommand(
        sourceId: sourceId,
        action: .focusTab,
        tabId: page.id,
        windowId: page.windowId
      ),
      demoMessage: "演示模式不会定位真实 Chrome 标签"
    )
  }

  func open(page: PageItem, sourceId: String) {
    enqueue(
      BrowserCommand(
        sourceId: sourceId,
        action: .openUrl,
        url: page.url
      ),
      demoMessage: "演示模式不会在 Chrome 中打开网页"
    )
  }

  func exportLibrary() {
    guard let snapshotRepository else {
      return
    }

    let warning = NSAlert()
    warning.messageText = "导出完整资料库？"
    warning.informativeText = "导出文件包含网页完整网址和可能存在的查询参数，请按浏览数据妥善保管。"
    warning.alertStyle = .informational
    warning.addButton(withTitle: "继续导出")
    warning.addButton(withTitle: "取消")
    guard warning.runModal() == .alertFirstButtonReturn else {
      return
    }

    let panel = NSSavePanel()
    panel.nameFieldStringValue = "页匣资料库.json"
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    do {
      try snapshotRepository.exportLibrary(to: url, applicationVersion: Self.applicationVersion)
      notice = AppNotice(kind: .success, message: "资料库已导出")
    } catch {
      notice = AppNotice(kind: .error, message: "导出失败：\(error.localizedDescription)")
    }
  }

  func importLibrary() {
    guard let snapshotRepository else {
      return
    }

    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }

    do {
      let imported = try snapshotRepository.importLibrary(from: url)
      refresh(force: true)
      notice = AppNotice(kind: .success, message: "已导入 \(imported.count) 个快照")
    } catch {
      notice = AppNotice(kind: .error, message: "导入失败：\(error.localizedDescription)")
    }
  }

  func revealExtensionDirectory() {
    do {
      let directory = try extensionPackageManager.prepare()
      NSWorkspace.shared.activateFileViewerSelecting([directory])
      notice = AppNotice(kind: .success, message: "扩展文件已准备好，请在 Chrome 中选择这个文件夹")
    } catch {
      notice = AppNotice(kind: .error, message: "扩展文件准备失败：\(error.localizedDescription)")
    }
  }

  func configureNativeHost() {
    do {
      let status = try nativeHostManager.install(extensionId: extensionId)
      nativeHostStatus = status
      extensionId = status.extensionId ?? extensionId
      notice = AppNotice(
        kind: .success,
        message: isDemoMode
          ? "已在隔离目录完成连接配置演示"
          : "本地连接已配置，页匣连接器会自动重试"
      )
    } catch {
      nativeHostStatus = nativeHostManager.inspect()
      notice = AppNotice(kind: .error, message: "连接配置失败：\(error.localizedDescription)")
    }
  }

  func removeNativeHost() {
    do {
      try nativeHostManager.uninstall()
      nativeHostStatus = nativeHostManager.inspect()
      notice = AppNotice(
        kind: .success,
        message: isDemoMode ? "已移除隔离连接配置" : "本地连接配置已移除"
      )
    } catch {
      notice = AppNotice(kind: .error, message: "移除连接失败：\(error.localizedDescription)")
    }
  }

  func dismissNotice() {
    notice = nil
  }

  private func enqueue(_ command: BrowserCommand, demoMessage: String) {
    if isDemoMode {
      notice = AppNotice(kind: .warning, message: demoMessage)
      return
    }

    guard isSourceConnected(command.sourceId) else {
      notice = AppNotice(kind: .warning, message: "Chrome 未连接，暂时无法执行这个操作")
      return
    }

    guard let commandRepository else {
      notice = AppNotice(kind: .error, message: "本地桥接尚未就绪")
      return
    }

    do {
      try commandRepository.enqueue(command)
      pendingCommands[command.id] = Date()
      notice = AppNotice(kind: .success, message: "命令已发送，等待 Chrome 响应")
    } catch {
      notice = AppNotice(kind: .error, message: "命令发送失败：\(error.localizedDescription)")
    }
  }

  private func checkCommandResults() {
    guard let commandRepository else {
      return
    }

    let now = Date()
    for (commandId, createdAt) in pendingCommands {
      do {
        if let result = try commandRepository.loadResult(commandId: commandId) {
          pendingCommands.removeValue(forKey: commandId)
          try commandRepository.removeResult(commandId: commandId)
          notice = AppNotice(
            kind: result.success ? .success : .error,
            message: result.message
          )
          continue
        }

        if now.timeIntervalSince(createdAt) >= 3 {
          pendingCommands.removeValue(forKey: commandId)
          notice = AppNotice(kind: .warning, message: "Chrome 未在 3 秒内响应，请检查连接状态")
        }
      } catch {
        notice = AppNotice(kind: .error, message: "读取命令结果失败：\(error.localizedDescription)")
      }
    }
  }

  private func localContentSignature() throws -> String {
    try [paths.live, paths.snapshots].map { directory in
      let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
      let date = attributes[.modificationDate] as? Date ?? .distantPast
      let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".json") }
        .count
      return "\(directory.lastPathComponent):\(date.timeIntervalSince1970):\(files)"
    }.joined(separator: "|")
  }

  private func reconcileSearchSelection() {
    guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      selectedSearchResultId = nil
      return
    }
    if let selectedSearchResultId,
       searchResults.contains(where: { $0.id == selectedSearchResultId }) {
      return
    }
    resetSearchSelection()
  }

  private func refreshSourceAvailability(now: Date = Date()) {
    let updated = Dictionary(uniqueKeysWithValues: liveStates.map { state in
      (
        state.source.id,
        state.source.isFresh(at: now)
          ? SourceAvailability.connected
          : SourceAvailability.stale
      )
    })
    if updated != sourceAvailabilityById {
      sourceAvailabilityById = updated
    }
  }
}
