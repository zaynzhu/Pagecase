import Foundation

public enum NativeHostState: Equatable, Sendable {
  case missing
  case ready
  case invalid
}

public struct NativeHostStatus: Equatable, Sendable {
  public let state: NativeHostState
  public let detail: String
  public let extensionId: String?

  public init(state: NativeHostState, detail: String, extensionId: String? = nil) {
    self.state = state
    self.detail = detail
    self.extensionId = extensionId
  }
}

public struct NativeHostManager: Sendable {
  public static let hostName = "com.zaynzhu.pagecase"

  public let manifestDirectory: URL
  public let bridgeURL: URL

  private let store: AtomicJSONStore

  public init(
    manifestDirectory: URL,
    bridgeURL: URL,
    store: AtomicJSONStore = AtomicJSONStore()
  ) {
    self.manifestDirectory = manifestDirectory.standardizedFileURL
    self.bridgeURL = bridgeURL.standardizedFileURL
    self.store = store
  }

  public var manifestURL: URL {
    manifestDirectory.appendingPathComponent("\(Self.hostName).json")
  }

  public static func defaultManifestDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> URL {
    if let override = environment["PAGECASE_NATIVE_HOST_ROOT"], !override.isEmpty {
      return URL(fileURLWithPath: override, isDirectory: true)
    }

    let applicationSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return applicationSupport
      .appendingPathComponent("Google/Chrome/NativeMessagingHosts", isDirectory: true)
  }

  public static func isValidExtensionId(_ value: String) -> Bool {
    value.range(of: "^[a-p]{32}$", options: .regularExpression) != nil
  }

  public func inspect(fileManager: FileManager = .default) -> NativeHostStatus {
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      return NativeHostStatus(state: .missing, detail: "尚未配置本地连接")
    }

    let manifest: NativeHostManifest
    do {
      manifest = try store.read(NativeHostManifest.self, from: manifestURL)
    } catch {
      return NativeHostStatus(state: .invalid, detail: "Host 清单无法读取或格式不正确")
    }

    guard manifest.name == Self.hostName, manifest.type == "stdio" else {
      return NativeHostStatus(state: .invalid, detail: "Host 清单名称或类型不正确")
    }
    guard manifest.path == bridgeURL.path else {
      return NativeHostStatus(state: .invalid, detail: "应用位置已变化，需要重新配置连接")
    }
    guard fileManager.isExecutableFile(atPath: bridgeURL.path) else {
      return NativeHostStatus(state: .invalid, detail: "当前应用内没有可执行的 Bridge")
    }
    guard manifest.allowedOrigins.count == 1,
          let extensionId = Self.extensionId(from: manifest.allowedOrigins[0]) else {
      return NativeHostStatus(state: .invalid, detail: "Host 允许的扩展标识不正确")
    }

    return NativeHostStatus(
      state: .ready,
      detail: "Host 已配置，等待扩展连接",
      extensionId: extensionId
    )
  }

  @discardableResult
  public func install(
    extensionId: String,
    fileManager: FileManager = .default
  ) throws -> NativeHostStatus {
    let normalizedId = extensionId
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard Self.isValidExtensionId(normalizedId) else {
      throw StoreError.invalidFile("扩展标识必须是 32 位 a-p 字符")
    }
    guard fileManager.isExecutableFile(atPath: bridgeURL.path) else {
      throw StoreError.invalidFile("当前应用内没有可执行的 Bridge")
    }

    try fileManager.createDirectory(
      at: manifestDirectory,
      withIntermediateDirectories: true
    )
    let manifest = NativeHostManifest(
      name: Self.hostName,
      description: "页匣 Native Messaging Bridge",
      path: bridgeURL.path,
      type: "stdio",
      allowedOrigins: ["chrome-extension://\(normalizedId)/"]
    )
    try store.write(manifest, to: manifestURL, prettyPrinted: true)
    try fileManager.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: manifestURL.path
    )

    let status = inspect(fileManager: fileManager)
    guard status.state == .ready else {
      throw StoreError.invalidFile("Host 清单写入后的核对失败")
    }
    return status
  }

  public func uninstall(fileManager: FileManager = .default) throws {
    guard fileManager.fileExists(atPath: manifestURL.path) else {
      return
    }
    try fileManager.removeItem(at: manifestURL)
  }

  private static func extensionId(from origin: String) -> String? {
    let prefix = "chrome-extension://"
    let suffix = "/"
    guard origin.hasPrefix(prefix), origin.hasSuffix(suffix) else {
      return nil
    }
    let start = origin.index(origin.startIndex, offsetBy: prefix.count)
    let end = origin.index(before: origin.endIndex)
    let value = String(origin[start..<end])
    return isValidExtensionId(value) ? value : nil
  }
}

private struct NativeHostManifest: Codable {
  let name: String
  let description: String
  let path: String
  let type: String
  let allowedOrigins: [String]

  enum CodingKeys: String, CodingKey {
    case name
    case description
    case path
    case type
    case allowedOrigins = "allowed_origins"
  }
}
