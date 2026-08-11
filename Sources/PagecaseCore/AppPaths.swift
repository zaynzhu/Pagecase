import Foundation

public struct AppPaths: Sendable {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  public static func defaultPaths(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppPaths {
    if let override = environment["PAGECASE_DATA_ROOT"], !override.isEmpty {
      return AppPaths(root: URL(fileURLWithPath: override, isDirectory: true))
    }

    let applicationSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return AppPaths(root: applicationSupport.appendingPathComponent("Pagecase", isDirectory: true))
  }

  public var live: URL { root.appendingPathComponent("live", isDirectory: true) }
  public var snapshots: URL { root.appendingPathComponent("snapshots", isDirectory: true) }
  public var commands: URL { root.appendingPathComponent("commands", isDirectory: true) }
  public var processing: URL { root.appendingPathComponent("processing", isDirectory: true) }
  public var results: URL { root.appendingPathComponent("results", isDirectory: true) }
  public var preferences: URL { root.appendingPathComponent("preferences.json") }
  public var chromeRestoredGroups: URL { root.appendingPathComponent("chrome-restored-groups.json") }

  public func createDirectories(fileManager: FileManager = .default) throws {
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: live, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: commands, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: processing, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: results, withIntermediateDirectories: true)
  }

  public func liveFile(sourceId: String) -> URL {
    live.appendingPathComponent("\(safeIdentifier(sourceId)).json")
  }

  public func snapshotFile(snapshotId: String) -> URL {
    snapshots.appendingPathComponent("\(safeIdentifier(snapshotId)).json")
  }

  public func commandFile(commandId: String) -> URL {
    commands.appendingPathComponent("\(safeIdentifier(commandId)).json")
  }

  public func processingFile(commandId: String) -> URL {
    processing.appendingPathComponent("\(safeIdentifier(commandId)).json")
  }

  public func resultFile(commandId: String) -> URL {
    results.appendingPathComponent("\(safeIdentifier(commandId)).json")
  }

  private func safeIdentifier(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
    return String(scalars)
  }
}
