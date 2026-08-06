import Foundation

public enum StoreError: LocalizedError, Equatable {
  case unsupportedSchema(Int)
  case invalidFile(String)
  case messageTooLarge(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version):
      return "不支持的数据版本：\(version)"
    case .invalidFile(let message):
      return "数据文件无效：\(message)"
    case .messageTooLarge(let size):
      return "消息大小 \(size) 字节，超过 4MB 上限"
    }
  }
}

public struct AtomicJSONStore: Sendable {
  public init() {}

  public func write<T: Encodable>(_ value: T, to url: URL, prettyPrinted: Bool = false) throws {
    let data = try PagecaseJSON.makeEncoder(prettyPrinted: prettyPrinted).encode(value)
    try data.write(to: url, options: .atomic)
  }

  public func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let data = try Data(contentsOf: url)
    return try PagecaseJSON.makeDecoder().decode(type, from: data)
  }
}
