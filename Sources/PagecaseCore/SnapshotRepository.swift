import Foundation

public struct SnapshotRepository: Sendable {
  public let paths: AppPaths
  private let store: AtomicJSONStore

  public init(paths: AppPaths, store: AtomicJSONStore = AtomicJSONStore()) throws {
    self.paths = paths
    self.store = store
    try paths.createDirectories()
  }

  public func saveLiveState(_ state: LiveState) throws {
    guard state.schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(state.schemaVersion)
    }
    try store.write(state, to: paths.liveFile(sourceId: state.source.id))
  }

  public func loadLiveStates() throws -> [LiveState] {
    try loadJSONFiles(in: paths.live, as: LiveState.self)
      .filter { $0.schemaVersion == PagecaseSchema.currentVersion }
      .sorted { $0.source.capturedAt > $1.source.capturedAt }
  }

  @discardableResult
  public func createSnapshot(
    from state: LiveState,
    name: String,
    now: Date = Date()
  ) throws -> SavedSnapshot {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw StoreError.invalidFile("快照名称不能为空")
    }

    let snapshot = SavedSnapshot(
      name: trimmedName,
      createdAt: now,
      sourceId: state.source.id,
      windows: state.windows
    )
    try saveSnapshot(snapshot)
    return snapshot
  }

  public func saveSnapshot(_ snapshot: SavedSnapshot) throws {
    guard snapshot.schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(snapshot.schemaVersion)
    }
    try store.write(snapshot, to: paths.snapshotFile(snapshotId: snapshot.id))
  }

  public func loadSnapshots() throws -> [SavedSnapshot] {
    try loadJSONFiles(in: paths.snapshots, as: SavedSnapshot.self)
      .filter { $0.schemaVersion == PagecaseSchema.currentVersion }
      .sorted { $0.createdAt > $1.createdAt }
  }

  public func renameSnapshot(_ snapshot: SavedSnapshot, to name: String, now: Date = Date()) throws -> SavedSnapshot {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw StoreError.invalidFile("快照名称不能为空")
    }

    var updated = snapshot
    updated.name = trimmedName
    updated.updatedAt = now
    try saveSnapshot(updated)
    return updated
  }

  public func deleteSnapshot(id: String) throws {
    let file = paths.snapshotFile(snapshotId: id)
    guard FileManager.default.fileExists(atPath: file.path) else {
      return
    }
    try FileManager.default.removeItem(at: file)
  }

  public func exportLibrary(to url: URL, applicationVersion: String) throws {
    let payload = LibraryExport(
      applicationVersion: applicationVersion,
      snapshots: try loadSnapshots()
    )
    try store.write(payload, to: url, prettyPrinted: true)
  }

  @discardableResult
  public func importLibrary(from url: URL, now: Date = Date()) throws -> [SavedSnapshot] {
    let payload = try store.read(LibraryExport.self, from: url)
    guard payload.schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(payload.schemaVersion)
    }

    let existingIds = Set(try loadSnapshots().map(\.id))
    var imported: [SavedSnapshot] = []

    for snapshot in payload.snapshots {
      guard snapshot.schemaVersion == PagecaseSchema.currentVersion else {
        throw StoreError.unsupportedSchema(snapshot.schemaVersion)
      }

      let importedSnapshot: SavedSnapshot
      if existingIds.contains(snapshot.id) || imported.contains(where: { $0.id == snapshot.id }) {
        importedSnapshot = SavedSnapshot(
          name: snapshot.name,
          createdAt: snapshot.createdAt,
          updatedAt: now,
          sourceId: snapshot.sourceId,
          windows: snapshot.windows
        )
      } else {
        importedSnapshot = snapshot
      }
      imported.append(importedSnapshot)
    }

    for snapshot in imported {
      try saveSnapshot(snapshot)
    }
    return imported
  }

  private func loadJSONFiles<T: Decodable>(in directory: URL, as type: T.Type) throws -> [T] {
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    return try urls
      .filter { $0.pathExtension == "json" }
      .map { try store.read(type, from: $0) }
  }
}
