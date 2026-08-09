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
    try PagecaseValidator.validate(state)
    try store.write(state, to: paths.liveFile(sourceId: state.source.id))
  }

  public func loadLiveStates() throws -> [LiveState] {
    let states = try loadJSONFiles(in: paths.live, as: LiveState.self)
    try states.forEach(PagecaseValidator.validate)
    return states.sorted { $0.source.capturedAt > $1.source.capturedAt }
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

  @discardableResult
  public func createGroupSnapshot(
    from group: TabGroup,
    in window: BrowserWindow,
    sourceId: String,
    name: String,
    now: Date = Date()
  ) throws -> SavedSnapshot {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw StoreError.invalidFile("快照名称不能为空")
    }

    let snapshotWindow = BrowserWindow(
      id: window.id,
      order: window.order,
      focused: window.focused,
      groups: [group],
      ungroupedTabs: []
    )
    let snapshot = SavedSnapshot(
      name: trimmedName,
      createdAt: now,
      sourceId: sourceId,
      scope: .group,
      windows: [snapshotWindow]
    )
    try saveSnapshot(snapshot)
    return snapshot
  }

  public func saveSnapshot(_ snapshot: SavedSnapshot) throws {
    try PagecaseValidator.validate(snapshot)
    let file = paths.snapshotFile(snapshotId: snapshot.id)
    try store.write(snapshot, to: file)
    let persisted = try store.read(SavedSnapshot.self, from: file)
    try PagecaseValidator.validate(persisted)
    let expectedData = try PagecaseJSON.makeEncoder().encode(snapshot)
    let persistedData = try Data(contentsOf: file)
    guard persistedData == expectedData else {
      throw StoreError.invalidFile("快照写入后的内容核对失败")
    }
  }

  public func loadSnapshots() throws -> [SavedSnapshot] {
    let snapshots = try loadJSONFiles(in: paths.snapshots, as: SavedSnapshot.self)
    try snapshots.forEach(PagecaseValidator.validate)
    return snapshots.sorted { $0.createdAt > $1.createdAt }
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

    try payload.snapshots.forEach(PagecaseValidator.validate)

    let existing = try loadSnapshots()
    var occupiedIds = Set(existing.map(\.id))
    var imported: [SavedSnapshot] = []

    for snapshot in payload.snapshots {
      let importedSnapshot: SavedSnapshot
      if occupiedIds.contains(snapshot.id) {
        importedSnapshot = SavedSnapshot(
          name: snapshot.name,
          createdAt: snapshot.createdAt,
          updatedAt: now,
          sourceId: snapshot.sourceId,
          scope: snapshot.scope,
          windows: snapshot.windows
        )
      } else {
        importedSnapshot = snapshot
      }
      occupiedIds.insert(importedSnapshot.id)
      imported.append(importedSnapshot)
    }

    try replaceSnapshotLibrary(with: existing + imported)
    return imported
  }

  private func replaceSnapshotLibrary(with snapshots: [SavedSnapshot]) throws {
    try snapshots.forEach(PagecaseValidator.validate)

    let fileManager = FileManager.default
    let token = UUID().uuidString.lowercased()
    let stagingRoot = paths.root.appendingPathComponent(".snapshot-import-\(token)", isDirectory: true)
    let stagingPaths = AppPaths(root: stagingRoot)
    let backup = paths.root.appendingPathComponent(".snapshots-backup-\(token)", isDirectory: true)

    defer {
      if fileManager.fileExists(atPath: stagingRoot.path) {
        try? fileManager.removeItem(at: stagingRoot)
      }
    }

    try stagingPaths.createDirectories(fileManager: fileManager)
    for snapshot in snapshots {
      try store.write(snapshot, to: stagingPaths.snapshotFile(snapshotId: snapshot.id))
    }

    let staged = try loadJSONFiles(in: stagingPaths.snapshots, as: SavedSnapshot.self)
    try staged.forEach(PagecaseValidator.validate)
    guard Set(staged.map(\.id)) == Set(snapshots.map(\.id)),
          staged.count == snapshots.count else {
      throw StoreError.invalidFile("导入暂存资料核对失败")
    }

    var originalMoved = false
    do {
      try fileManager.moveItem(at: paths.snapshots, to: backup)
      originalMoved = true
      try fileManager.moveItem(at: stagingPaths.snapshots, to: paths.snapshots)
      try? fileManager.removeItem(at: backup)
    } catch {
      if originalMoved, !fileManager.fileExists(atPath: paths.snapshots.path) {
        do {
          try fileManager.moveItem(at: backup, to: paths.snapshots)
        } catch {
          throw StoreError.invalidFile("导入失败，原资料目录恢复失败：\(error.localizedDescription)")
        }
      }
      throw error
    }
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
