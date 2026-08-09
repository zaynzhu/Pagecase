import AppKit
import Foundation
import PagecaseCore

enum NavigationItem: String, CaseIterable, Identifiable {
  case chromeLive
  case chromeLibrary
  case safariImport
  case safariLibrary
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .chromeLive:
      return "现在"
    case .chromeLibrary:
      return "快照"
    case .safariImport:
      return "按需收纳"
    case .safariLibrary:
      return "合集"
    case .settings:
      return "设置"
    }
  }

  var symbol: String {
    switch self {
    case .chromeLive:
      return "rectangle.stack"
    case .chromeLibrary:
      return "archivebox"
    case .safariImport:
      return "safari"
    case .safariLibrary:
      return "books.vertical"
    case .settings:
      return "gearshape"
    }
  }

  var browserKind: BrowserKind? {
    switch self {
    case .chromeLive, .chromeLibrary:
      return .chrome
    case .safariImport, .safariLibrary:
      return .safari
    case .settings:
      return nil
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

struct GroupFocusRequest: Equatable {
  let id = UUID()
  let scope: String
  let windowId: Int
  let groupId: Int

  var anchorId: String {
    "group-\(windowId)-\(groupId)"
  }
}

@MainActor
final class AppModel: ObservableObject {
  static let applicationVersion = "0.6.0"

  @Published var selection: NavigationItem = .chromeLive
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
  @Published private(set) var collapsedGroupKeys: Set<String> = []
  @Published private(set) var groupFocusRequest: GroupFocusRequest?
  @Published private(set) var safariCapture: SafariCapture?
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
  private let displayPreferencesRepository: DisplayPreferencesRepository
  private let safariCapturer: any SafariCapturing
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
    extensionDirectory: URL? = nil,
    safariCapturer: (any SafariCapturing)? = nil
  ) {
    self.paths = paths
    self.isDemoMode = isDemoMode
    self.isPerformanceMode = isPerformanceMode
    self.safariCapturer = safariCapturer
      ?? (isDemoMode ? DemoSafariCapturer() : SystemSafariCapturer())
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
    displayPreferencesRepository = DisplayPreferencesRepository(paths: paths)
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

    do {
      collapsedGroupKeys = try displayPreferencesRepository.load().collapsedGroupKeys
    } catch {
      notice = AppNotice(kind: .error, message: "读取折叠状态失败：\(error.localizedDescription)")
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
       let selected = librarySnapshots.first(where: { $0.id == selectedSnapshotId }) {
      return selected
    }
    return librarySnapshots.first
  }

  var snapshotLibraryItems: [SnapshotLibraryItem] {
    SnapshotLibraryOrganizer.organize(librarySnapshots)
  }

  var chromeSnapshots: [SavedSnapshot] {
    snapshots.filter { $0.sourceKind == .chrome }
  }

  var safariCollections: [SavedSnapshot] {
    snapshots.filter { $0.sourceKind == .safari }
  }

  var librarySnapshots: [SavedSnapshot] {
    selection == .safariLibrary ? safariCollections : chromeSnapshots
  }

  var libraryBrowserKind: BrowserKind {
    selection == .safariLibrary ? .safari : .chrome
  }

  var libraryTitle: String {
    libraryBrowserKind == .safari ? "Safari 合集" : "Chrome 快照"
  }

  var libraryEmptyTitle: String {
    libraryBrowserKind == .safari ? "还没有 Safari 合集" : "还没有 Chrome 快照"
  }

  var libraryEmptyMessage: String {
    libraryBrowserKind == .safari
      ? "先打开“按需收纳”，读取 Safari 当前窗口并保存。"
      : "在 Chrome 的“现在”页面保存当前现场或单个标签组。"
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

  func selectNavigation(_ item: NavigationItem) {
    selection = item
    searchQuery = ""
    switch item {
    case .chromeLibrary:
      if !chromeSnapshots.contains(where: { $0.id == selectedSnapshotId }) {
        selectedSnapshotId = chromeSnapshots.first?.id
      }
    case .safariLibrary:
      if !safariCollections.contains(where: { $0.id == selectedSnapshotId }) {
        selectedSnapshotId = safariCollections.first?.id
      }
    case .chromeLive, .safariImport, .settings:
      break
    }
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

  func isSnapshotActionAvailable(_ snapshot: SavedSnapshot) -> Bool {
    snapshot.sourceKind == .safari || isSourceActionAvailable(snapshot.sourceId)
  }

  func snapshotActionTitle(for snapshot: SavedSnapshot) -> String {
    if snapshot.sourceKind == .safari {
      return "在 Safari 打开"
    }
    return isSourceActionAvailable(snapshot.sourceId) ? "打开" : "Chrome 未连接"
  }

  func snapshotGroupActionTitle(for sourceId: String) -> String {
    isSourceActionAvailable(sourceId) ? "恢复整组" : "Chrome 未连接"
  }

  func isGroupExpanded(
    scope: String,
    windowId: Int,
    groupId: Int?
  ) -> Bool {
    let key = DisplayPreferences.groupKey(
      scope: scope,
      windowId: windowId,
      groupId: groupId
    )
    return !collapsedGroupKeys.contains(key)
  }

  func toggleGroupExpansion(
    scope: String,
    windowId: Int,
    groupId: Int?
  ) {
    let key = DisplayPreferences.groupKey(
      scope: scope,
      windowId: windowId,
      groupId: groupId
    )
    var updatedKeys = collapsedGroupKeys
    if !updatedKeys.insert(key).inserted {
      updatedKeys.remove(key)
    }

    do {
      try displayPreferencesRepository.save(
        DisplayPreferences(collapsedGroupKeys: updatedKeys)
      )
      collapsedGroupKeys = updatedKeys
    } catch {
      notice = AppNotice(kind: .error, message: "保存折叠状态失败：\(error.localizedDescription)")
    }
  }

  func isSearchActionAvailable(_ result: SearchResult) -> Bool {
    if result.target == .group {
      return true
    }
    if result.kind == .snapshot, result.sourceKind == .safari {
      return true
    }
    return isSourceActionAvailable(result.sourceId)
  }

  func searchActionTitle(for result: SearchResult) -> String {
    if result.target == .group {
      return "查看"
    }
    switch result.kind {
    case .live:
      return liveActionTitle(for: result.sourceId)
    case .snapshot:
      if result.sourceKind == .safari {
        return "在 Safari 打开"
      }
      return isSourceActionAvailable(result.sourceId) ? "打开" : "Chrome 未连接"
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

  func createGroupSnapshot(
    sourceId: String,
    windowId: Int,
    groupId: Int,
    name: String
  ) -> Bool {
    guard let state = liveStates.first(where: { $0.source.id == sourceId }),
          let window = state.windows.first(where: { $0.id == windowId }),
          let group = window.groups.first(where: { $0.id == groupId }),
          let snapshotRepository else {
      notice = AppNotice(kind: .warning, message: "这个标签组已经不在当前 Chrome 现场中")
      return false
    }

    do {
      let snapshot = try snapshotRepository.createGroupSnapshot(
        from: group,
        in: window,
        sourceId: sourceId,
        sourceLabel: state.source.label,
        name: name
      )
      selectedSnapshotId = snapshot.id
      refresh(force: true)
      notice = AppNotice(
        kind: .success,
        message: "已从磁盘核对保存「\(group.displayTitle)」的 \(snapshot.tabCount) 个网页，Chrome 保持不变"
      )
      return true
    } catch {
      notice = AppNotice(kind: .error, message: error.localizedDescription)
      return false
    }
  }

  func captureSafariCurrentWindow() {
    do {
      safariCapture = try safariCapturer.captureCurrentWindow()
      let skipped = safariCapture?.skippedPageCount ?? 0
      notice = AppNotice(
        kind: skipped > 0 ? .warning : .success,
        message: skipped > 0
          ? "已读取 \(safariCapture?.pages.count ?? 0) 个网页，并忽略 \(skipped) 个非网页标签"
          : "已读取 Safari 当前窗口的 \(safariCapture?.pages.count ?? 0) 个网页"
      )
    } catch {
      safariCapture = nil
      notice = AppNotice(kind: .error, message: error.localizedDescription)
    }
  }

  func clearSafariCapture() {
    safariCapture = nil
  }

  func saveSafariCollection(name: String) -> Bool {
    guard let safariCapture, let snapshotRepository else {
      notice = AppNotice(kind: .warning, message: "请先读取 Safari 当前窗口")
      return false
    }

    do {
      let snapshot = try snapshotRepository.createSafariCollection(
        from: safariCapture,
        name: name
      )
      selectedSnapshotId = snapshot.id
      self.safariCapture = nil
      refresh(force: true)
      selectNavigation(.safariLibrary)
      notice = AppNotice(
        kind: .success,
        message: "已从磁盘核对保存 \(snapshot.tabCount) 个 Safari 网页，Safari 保持不变"
      )
      return true
    } catch {
      notice = AppNotice(kind: .error, message: error.localizedDescription)
      return false
    }
  }

  func showSavedGroup(_ coverage: GroupSnapshotCoverage) {
    guard coverage.isComplete,
          let snapshot = coverage.snapshot,
          let windowId = coverage.windowId,
          let groupId = coverage.groupId else {
      notice = AppNotice(kind: .warning, message: "暂时找不到这个标签组对应的快照")
      return
    }

    showSnapshotGroup(snapshotId: snapshot.id, windowId: windowId, groupId: groupId)
  }

  func showSearchGroup(_ result: SearchResult) {
    guard result.target == .group,
          let windowId = result.windowId,
          let groupId = result.groupId,
          searchGroup(for: result) != nil else {
      notice = AppNotice(kind: .warning, message: "这个标签组已经不在当前资料中")
      return
    }

    switch result.kind {
    case .live:
      let scope = "live:\(result.sourceId)"
      expandGroupIfNeeded(scope: scope, windowId: windowId, groupId: groupId)
      selectedSourceId = result.sourceId
      selection = .chromeLive
      searchQuery = ""
      groupFocusRequest = GroupFocusRequest(
        scope: scope,
        windowId: windowId,
        groupId: groupId
      )
    case .snapshot:
      guard let snapshotId = result.snapshotId else {
        notice = AppNotice(kind: .warning, message: "这个搜索结果缺少快照位置")
        return
      }
      showSnapshotGroup(snapshotId: snapshotId, windowId: windowId, groupId: groupId)
    }
  }

  func searchGroup(for result: SearchResult) -> TabGroup? {
    guard result.target == .group,
          let windowId = result.windowId,
          let groupId = result.groupId else {
      return nil
    }

    switch result.kind {
    case .live:
      return liveStates
        .first(where: { $0.source.id == result.sourceId })?
        .windows.first(where: { $0.id == windowId })?
        .groups.first(where: { $0.id == groupId })
    case .snapshot:
      guard let snapshotId = result.snapshotId else {
        return nil
      }
      return snapshots
        .first(where: { $0.id == snapshotId })?
        .windows.first(where: { $0.id == windowId })?
        .groups.first(where: { $0.id == groupId })
    }
  }

  func consumeGroupFocusRequest(scope: String) -> GroupFocusRequest? {
    guard groupFocusRequest?.scope == scope else {
      return nil
    }
    defer { groupFocusRequest = nil }
    return groupFocusRequest
  }

  func renameSnapshot(_ snapshot: SavedSnapshot, name: String) -> Bool {
    guard let snapshotRepository else {
      return false
    }

    do {
      let updated = try snapshotRepository.renameSnapshot(snapshot, to: name)
      selectedSnapshotId = updated.id
      refresh(force: true)
      notice = AppNotice(
        kind: .success,
        message: snapshot.sourceKind == .safari ? "合集已重命名" : "快照已重命名"
      )
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
      let nextVersionId = SnapshotLibraryOrganizer.groupSeries(
        containing: snapshot.id,
        in: snapshots
      )?.snapshots.first(where: { $0.id != snapshot.id })?.id
      let nextBrowserSnapshotId = snapshots.first(where: {
        $0.sourceKind == snapshot.sourceKind && $0.id != snapshot.id
      })?.id
      try snapshotRepository.deleteSnapshot(id: snapshot.id)
      if selectedSnapshotId == snapshot.id {
        selectedSnapshotId = nextVersionId ?? nextBrowserSnapshotId
      }
      refresh(force: true)
      notice = AppNotice(
        kind: .success,
        message: snapshot.sourceKind == .safari ? "合集已删除" : "快照已删除"
      )
    } catch {
      notice = AppNotice(kind: .error, message: "删除失败：\(error.localizedDescription)")
    }
  }

  func activate(_ result: SearchResult) {
    if result.target == .group {
      showSearchGroup(result)
      return
    }

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
      guard let url = result.url else {
        notice = AppNotice(kind: .error, message: "网页地址不完整")
        return
      }
      if result.sourceKind == .safari {
        openInSafari(urls: [url])
        return
      }
      enqueue(
        BrowserCommand(
          sourceId: result.sourceId,
          action: .openUrl,
          url: url
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
          : "对应浏览器暂时无法打开这个快照网页"
      )
      return
    }
    activate(result)
  }

  private func showSnapshotGroup(
    snapshotId: String,
    windowId: Int,
    groupId: Int
  ) {
    let scope = "snapshot:\(snapshotId)"
    expandGroupIfNeeded(scope: scope, windowId: windowId, groupId: groupId)
    selectedSnapshotId = snapshotId
    selection = .chromeLibrary
    searchQuery = ""
    groupFocusRequest = GroupFocusRequest(
      scope: scope,
      windowId: windowId,
      groupId: groupId
    )
  }

  private func expandGroupIfNeeded(
    scope: String,
    windowId: Int,
    groupId: Int
  ) {
    if !isGroupExpanded(scope: scope, windowId: windowId, groupId: groupId) {
      toggleGroupExpansion(scope: scope, windowId: windowId, groupId: groupId)
    }
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

  func openSafari(page: PageItem) {
    openInSafari(urls: [page.url])
  }

  func openSafariCollection(_ snapshot: SavedSnapshot) {
    guard snapshot.sourceKind == .safari else {
      return
    }
    let urls = snapshot.windows
      .flatMap { $0.groups.flatMap(\.tabs) + $0.ungroupedTabs }
      .map(\.url)
    openInSafari(urls: urls)
  }

  func restore(group: TabGroup, sourceId: String) {
    enqueue(
      BrowserCommand(
        sourceId: sourceId,
        action: .restoreGroup,
        groupTitle: group.title,
        groupColor: group.color,
        urls: group.tabs.map(\.url)
      ),
      demoMessage: "演示模式不会在 Chrome 中恢复标签组"
    )
  }

  private func openInSafari(urls: [String]) {
    let webURLs = urls.compactMap(URL.init(string:))
    guard !webURLs.isEmpty else {
      notice = AppNotice(kind: .warning, message: "没有可以在 Safari 打开的网页")
      return
    }
    if isDemoMode {
      notice = AppNotice(kind: .warning, message: "演示模式不会打开真实 Safari")
      return
    }

    guard let safariURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.apple.Safari"
    ) else {
      notice = AppNotice(kind: .error, message: "无法找到 Safari 应用")
      return
    }
    NSWorkspace.shared.open(
      webURLs,
      withApplicationAt: safariURL,
      configuration: NSWorkspace.OpenConfiguration(),
      completionHandler: nil
    )
    notice = AppNotice(
      kind: .success,
      message: "已请求 Safari 打开 \(webURLs.count) 个网页"
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
      notice = AppNotice(kind: .success, message: "已导入 \(imported.count) 份本地资料")
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
      pendingCommands[command.id] = Date().addingTimeInterval(
        command.action == .restoreGroup ? 30 : 3
      )
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
    for (commandId, deadline) in pendingCommands {
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

        if now >= deadline {
          pendingCommands.removeValue(forKey: commandId)
          notice = AppNotice(kind: .warning, message: "Chrome 未及时响应，请检查连接状态")
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
