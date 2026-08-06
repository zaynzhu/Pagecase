import Foundation

public struct ExtensionPackageManager: Sendable {
  public static let requiredFiles = [
    "manifest.json",
    "background.js",
    "commands.js",
    "snapshot.js",
    "README.txt"
  ]

  public let sourceDirectory: URL
  public let destinationDirectory: URL

  public init(sourceDirectory: URL, destinationDirectory: URL) {
    self.sourceDirectory = sourceDirectory.standardizedFileURL
    self.destinationDirectory = destinationDirectory.standardizedFileURL
  }

  public func isSourceAvailable(fileManager: FileManager = .default) -> Bool {
    Self.requiredFiles.allSatisfy { file in
      var isDirectory = ObjCBool(false)
      let exists = fileManager.fileExists(
        atPath: sourceDirectory.appendingPathComponent(file).path,
        isDirectory: &isDirectory
      )
      return exists && !isDirectory.boolValue
    }
  }

  @discardableResult
  public func prepare(fileManager: FileManager = .default) throws -> URL {
    guard isSourceAvailable(fileManager: fileManager) else {
      throw StoreError.invalidFile("当前应用包没有包含完整的 Chrome 扩展文件")
    }

    let parent = destinationDirectory.deletingLastPathComponent()
    let token = UUID().uuidString.lowercased()
    let staging = parent.appendingPathComponent(".extension-staging-\(token)", isDirectory: true)
    let backup = parent.appendingPathComponent(".extension-backup-\(token)", isDirectory: true)
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

    defer {
      if fileManager.fileExists(atPath: staging.path) {
        try? fileManager.removeItem(at: staging)
      }
    }

    for file in Self.requiredFiles {
      let source = sourceDirectory.appendingPathComponent(file)
      let staged = staging.appendingPathComponent(file)
      try fileManager.copyItem(at: source, to: staged)
      guard try Data(contentsOf: source) == Data(contentsOf: staged) else {
        throw StoreError.invalidFile("扩展文件复制核对失败：\(file)")
      }
    }

    var originalMoved = false
    do {
      if fileManager.fileExists(atPath: destinationDirectory.path) {
        try fileManager.moveItem(at: destinationDirectory, to: backup)
        originalMoved = true
      }
      try fileManager.moveItem(at: staging, to: destinationDirectory)
      if originalMoved {
        try? fileManager.removeItem(at: backup)
      }
    } catch {
      if originalMoved, !fileManager.fileExists(atPath: destinationDirectory.path) {
        do {
          try fileManager.moveItem(at: backup, to: destinationDirectory)
        } catch {
          throw StoreError.invalidFile("扩展准备失败，原文件恢复失败：\(error.localizedDescription)")
        }
      }
      throw error
    }

    return destinationDirectory
  }
}
