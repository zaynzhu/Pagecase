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

@MainActor
final class AppModel: ObservableObject {
  static let applicationVersion = "0.1.0"

  @Published var selection: NavigationItem = .live
  @Published var liveStates: [LiveState] = []
  @Published var snapshots: [SavedSnapshot] = []
  @Published var selectedSourceId: String?
  @Published var selectedSnapshotId: String?
  @Published var searchQuery = ""
  @Published var searchFocusRequest = 0
  @Published var notice: AppNotice?

  let paths: AppPaths
  let isDemoMode: Bool
  let isPerformanceMode: Bool

  private let snapshotRepository: SnapshotRepository?
  private let commandRepository: CommandRepository?
  private var pendingCommands: [String: Date] = [:]
  private var contentSignature: String?

  static func make() -> AppModel {
    let environment = ProcessInfo.processInfo.environment
    let fallback = AppPaths(
      root: FileManager.default.temporaryDirectory
        .appendingPathComponent("Pagecase-Fallback", isDirectory: true)
    )
    let paths = (try? AppPaths.defaultPaths(environment: environment)) ?? fallback
    let isPerformanceMode = environment["PAGECASE_PERFORMANCE"] == "1"
      || ProcessInfo.processInfo.arguments.contains("--performance")
    return AppModel(
      paths: paths,
      isDemoMode: environment["PAGECASE_DEMO"] == "1"
        || ProcessInfo.processInfo.arguments.contains("--demo")
        || isPerformanceMode,
      isPerformanceMode: isPerformanceMode
    )
  }

  init(paths: AppPaths, isDemoMode: Bool, isPerformanceMode: Bool = false) {
    self.paths = paths
    self.isDemoMode = isDemoMode
    self.isPerformanceMode = isPerformanceMode

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

  var totalLiveTabs: Int {
    liveStates.reduce(0) { $0 + $1.tabCount }
  }

  var hasConnectedSource: Bool {
    liveStates.contains { isSourceConnected($0.source.id) }
  }

  func isSourceConnected(_ sourceId: String, now: Date = Date()) -> Bool {
    guard let state = liveStates.first(where: { $0.source.id == sourceId }) else {
      return false
    }
    return now.timeIntervalSince(state.source.capturedAt) <= 30
  }

  func requestSearchFocus() {
    searchFocusRequest += 1
  }

  func refresh(force: Bool = false) {
    guard let snapshotRepository else {
      return
    }

    do {
      let signature = try localContentSignature()
      if !force, signature == contentSignature {
        checkCommandResults()
        return
      }

      liveStates = try snapshotRepository.loadLiveStates()
      snapshots = try snapshotRepository.loadSnapshots()
      contentSignature = signature

      if selectedSourceId == nil || !liveStates.contains(where: { $0.source.id == selectedSourceId }) {
        selectedSourceId = liveStates.first?.source.id
      }
      if selectedSnapshotId == nil || !snapshots.contains(where: { $0.id == selectedSnapshotId }) {
        selectedSnapshotId = snapshots.first?.id
      }

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
        message: "已保存 \(snapshot.tabCount) 个网页，Chrome 保持不变"
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
}
