import Foundation

public struct ChromeRestoredGroupRecord: Codable, Equatable, Sendable {
  public let sourceId: String
  public let snapshotId: String
  public let originalGroupId: Int
  public let restoredGroupId: Int
  public let restoredAt: Date

  public init(
    sourceId: String,
    snapshotId: String,
    originalGroupId: Int,
    restoredGroupId: Int,
    restoredAt: Date = Date()
  ) {
    self.sourceId = sourceId
    self.snapshotId = snapshotId
    self.originalGroupId = originalGroupId
    self.restoredGroupId = restoredGroupId
    self.restoredAt = restoredAt
  }

  public func validate() throws {
    guard !sourceId.isEmpty,
          sourceId.utf8.count <= 512,
          !snapshotId.isEmpty,
          snapshotId.utf8.count <= 512,
          originalGroupId >= 0,
          restoredGroupId >= 0 else {
      throw StoreError.invalidFile("Chrome 恢复组记录无效")
    }
  }

  fileprivate var key: String {
    "\(sourceId):\(snapshotId):\(originalGroupId)"
  }
}

public struct ChromeRestoredGroupIndex: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public private(set) var records: [ChromeRestoredGroupRecord]

  public init(
    schemaVersion: Int = PagecaseSchema.currentVersion,
    records: [ChromeRestoredGroupRecord] = []
  ) {
    self.schemaVersion = schemaVersion
    self.records = records
  }

  public func validate() throws {
    guard schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(schemaVersion)
    }
    try records.forEach { try $0.validate() }
    guard Set(records.map(\.key)).count == records.count else {
      throw StoreError.invalidFile("Chrome 恢复组记录存在重复项")
    }
  }

  public func record(
    sourceId: String,
    snapshotId: String,
    originalGroupId: Int
  ) -> ChromeRestoredGroupRecord? {
    records.first {
      $0.sourceId == sourceId
        && $0.snapshotId == snapshotId
        && $0.originalGroupId == originalGroupId
    }
  }

  fileprivate mutating func replace(with record: ChromeRestoredGroupRecord) {
    records.removeAll { $0.key == record.key }
    records.append(record)
    records.sort { $0.restoredAt > $1.restoredAt }
  }
}

public struct ChromeRestoredGroupRepository: Sendable {
  private let file: URL
  private let store: AtomicJSONStore

  public init(paths: AppPaths, store: AtomicJSONStore = AtomicJSONStore()) {
    file = paths.chromeRestoredGroups
    self.store = store
  }

  public func load() throws -> ChromeRestoredGroupIndex {
    guard FileManager.default.fileExists(atPath: file.path) else {
      return ChromeRestoredGroupIndex()
    }
    let index = try store.read(ChromeRestoredGroupIndex.self, from: file)
    try index.validate()
    return index
  }

  @discardableResult
  public func save(_ record: ChromeRestoredGroupRecord) throws -> ChromeRestoredGroupIndex {
    try record.validate()
    var index = try load()
    index.replace(with: record)
    try index.validate()
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try store.write(index, to: file)
    return index
  }
}
