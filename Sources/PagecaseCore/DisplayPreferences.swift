import Foundation

public struct DisplayPreferences: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public var collapsedGroupKeys: Set<String>

  public init(
    schemaVersion: Int = PagecaseSchema.currentVersion,
    collapsedGroupKeys: Set<String> = []
  ) {
    self.schemaVersion = schemaVersion
    self.collapsedGroupKeys = collapsedGroupKeys
  }

  public func validate() throws {
    guard schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(schemaVersion)
    }
    guard collapsedGroupKeys.allSatisfy({
      !$0.isEmpty && $0.utf8.count <= 512
    }) else {
      throw StoreError.invalidFile("折叠状态标识无效")
    }
  }

  public static func groupKey(
    scope: String,
    windowId: Int,
    groupId: Int?
  ) -> String {
    let groupComponent = groupId.map(String.init) ?? "ungrouped"
    return "\(scope):window:\(windowId):group:\(groupComponent)"
  }
}

public struct DisplayPreferencesRepository: Sendable {
  private let file: URL
  private let store: AtomicJSONStore

  public init(paths: AppPaths, store: AtomicJSONStore = AtomicJSONStore()) {
    file = paths.preferences
    self.store = store
  }

  public func load() throws -> DisplayPreferences {
    guard FileManager.default.fileExists(atPath: file.path) else {
      return DisplayPreferences()
    }
    let preferences = try store.read(DisplayPreferences.self, from: file)
    try preferences.validate()
    return preferences
  }

  public func save(_ preferences: DisplayPreferences) throws {
    try preferences.validate()
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try store.write(preferences, to: file)
  }
}
