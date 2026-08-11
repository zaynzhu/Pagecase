import Foundation

public enum BrowserCommandAction: String, Codable, Sendable {
  case focusTab
  case openUrl
  case restoreGroup
}

public enum BrowserCommandFailureStage: String, Codable, Sendable {
  case validation
  case creatingTabs
  case groupingTabs
  case updatingGroup
}

public struct BrowserCommand: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: String
  public let sourceId: String
  public let action: BrowserCommandAction
  public let createdAt: Date
  public let tabId: Int?
  public let windowId: Int?
  public let url: String?
  public let groupTitle: String?
  public let groupColor: ChromeGroupColor?
  public let urls: [String]?

  public init(
    schemaVersion: Int = 1,
    id: String = UUID().uuidString.lowercased(),
    sourceId: String,
    action: BrowserCommandAction,
    createdAt: Date = Date(),
    tabId: Int? = nil,
    windowId: Int? = nil,
    url: String? = nil,
    groupTitle: String? = nil,
    groupColor: ChromeGroupColor? = nil,
    urls: [String]? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.sourceId = sourceId
    self.action = action
    self.createdAt = createdAt
    self.tabId = tabId
    self.windowId = windowId
    self.url = url
    self.groupTitle = groupTitle
    self.groupColor = groupColor
    self.urls = urls
  }

  public func validate() throws {
    guard schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(schemaVersion)
    }

    switch action {
    case .focusTab:
      guard tabId != nil,
            windowId != nil,
            url == nil,
            groupTitle == nil,
            groupColor == nil,
            urls == nil else {
        throw StoreError.invalidFile("定位命令参数不完整")
      }
    case .openUrl:
      guard tabId == nil,
            windowId == nil,
            let url,
            Self.isWebURL(url),
            groupTitle == nil,
            groupColor == nil,
            urls == nil else {
        throw StoreError.invalidFile("打开命令必须包含有效的 http/https 网址")
      }
    case .restoreGroup:
      guard tabId == nil,
            windowId == nil,
            url == nil,
            groupTitle != nil,
            groupColor != nil,
            let urls,
            !urls.isEmpty,
            urls.allSatisfy(Self.isWebURL) else {
        throw StoreError.invalidFile("恢复标签组命令参数不完整")
      }
    }
  }

  private static func isWebURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased() else {
      return false
    }
    return scheme == "http" || scheme == "https"
  }
}

public struct BrowserCommandResult: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: String
  public let sourceId: String
  public let success: Bool
  public let message: String
  public let action: BrowserCommandAction?
  public let createdTabCount: Int?
  public let groupCreated: Bool?
  public let restoredGroupId: Int?
  public let failureStage: BrowserCommandFailureStage?
  public let completedAt: Date

  public init(
    schemaVersion: Int = 1,
    id: String,
    sourceId: String,
    success: Bool,
    message: String,
    action: BrowserCommandAction? = nil,
    createdTabCount: Int? = nil,
    groupCreated: Bool? = nil,
    restoredGroupId: Int? = nil,
    failureStage: BrowserCommandFailureStage? = nil,
    completedAt: Date = Date()
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.sourceId = sourceId
    self.success = success
    self.message = message
    self.action = action
    self.createdTabCount = createdTabCount
    self.groupCreated = groupCreated
    self.restoredGroupId = restoredGroupId
    self.failureStage = failureStage
    self.completedAt = completedAt
  }
}

public struct CommandRepository: Sendable {
  public let paths: AppPaths
  private let store: AtomicJSONStore

  public init(paths: AppPaths, store: AtomicJSONStore = AtomicJSONStore()) throws {
    self.paths = paths
    self.store = store
    try paths.createDirectories()
  }

  public func enqueue(_ command: BrowserCommand) throws {
    try command.validate()
    try store.write(command, to: paths.commandFile(commandId: command.id))
  }

  public func loadPendingCommands() throws -> [BrowserCommand] {
    try loadCommands(in: paths.commands)
  }

  public func claim(_ command: BrowserCommand) throws {
    let source = paths.commandFile(commandId: command.id)
    let destination = paths.processingFile(commandId: command.id)
    try FileManager.default.moveItem(at: source, to: destination)
  }

  public func loadProcessingCommands() throws -> [BrowserCommand] {
    try loadCommands(in: paths.processing)
  }

  public func saveResult(_ result: BrowserCommandResult) throws {
    try store.write(result, to: paths.resultFile(commandId: result.id))
    let processing = paths.processingFile(commandId: result.id)
    if FileManager.default.fileExists(atPath: processing.path) {
      try FileManager.default.removeItem(at: processing)
    }
  }

  public func loadResult(commandId: String) throws -> BrowserCommandResult? {
    let file = paths.resultFile(commandId: commandId)
    guard FileManager.default.fileExists(atPath: file.path) else {
      return nil
    }
    return try store.read(BrowserCommandResult.self, from: file)
  }

  public func removeResult(commandId: String) throws {
    let file = paths.resultFile(commandId: commandId)
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
  }

  private func loadCommands(in directory: URL) throws -> [BrowserCommand] {
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    return try urls
      .filter { $0.pathExtension == "json" }
      .map { try store.read(BrowserCommand.self, from: $0) }
      .sorted { $0.createdAt < $1.createdAt }
  }
}
