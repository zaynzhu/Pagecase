import Foundation

public struct NativeInboundMessage: Codable, Sendable {
  public let type: String
  public let payload: LiveState?
  public let commandId: String?
  public let sourceId: String?
  public let success: Bool?
  public let message: String?

  public init(
    type: String,
    payload: LiveState? = nil,
    commandId: String? = nil,
    sourceId: String? = nil,
    success: Bool? = nil,
    message: String? = nil
  ) {
    self.type = type
    self.payload = payload
    self.commandId = commandId
    self.sourceId = sourceId
    self.success = success
    self.message = message
  }
}

public struct NativeOutboundMessage: Codable, Sendable {
  public let type: String
  public let schemaVersion: Int
  public let commandId: String?
  public let sourceId: String?
  public let tabId: Int?
  public let windowId: Int?
  public let url: String?

  public init(command: BrowserCommand) {
    self.type = command.action.rawValue
    self.schemaVersion = command.schemaVersion
    self.commandId = command.id
    self.sourceId = command.sourceId
    self.tabId = command.tabId
    self.windowId = command.windowId
    self.url = command.url
  }

  public init(type: String) {
    self.type = type
    self.schemaVersion = PagecaseSchema.currentVersion
    self.commandId = nil
    self.sourceId = nil
    self.tabId = nil
    self.windowId = nil
    self.url = nil
  }
}

public enum NativeMessageFramer {
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let payload = try PagecaseJSON.makeEncoder().encode(value)
    guard payload.count <= PagecaseSchema.nativeMessageLimit else {
      throw StoreError.messageTooLarge(payload.count)
    }

    var length = UInt32(payload.count).littleEndian
    var framed = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
    framed.append(payload)
    return framed
  }

  public static func decode<T: Decodable>(_ type: T.Type, from framedData: Data) throws -> T {
    guard framedData.count >= MemoryLayout<UInt32>.size else {
      throw StoreError.invalidFile("Native Messaging 长度前缀缺失")
    }

    let lengthData = framedData.prefix(MemoryLayout<UInt32>.size)
    let expectedLength = lengthData.withUnsafeBytes { bytes in
      UInt32(littleEndian: bytes.loadUnaligned(as: UInt32.self))
    }
    guard expectedLength <= PagecaseSchema.nativeMessageLimit else {
      throw StoreError.messageTooLarge(Int(expectedLength))
    }

    let payload = framedData.dropFirst(MemoryLayout<UInt32>.size)
    guard payload.count == Int(expectedLength) else {
      throw StoreError.invalidFile("Native Messaging 消息长度不一致")
    }
    return try PagecaseJSON.makeDecoder().decode(type, from: Data(payload))
  }

  public static func readMessage<T: Decodable>(_ type: T.Type, from handle: FileHandle) throws -> T? {
    let lengthData = try handle.read(upToCount: MemoryLayout<UInt32>.size) ?? Data()
    if lengthData.isEmpty {
      return nil
    }
    guard lengthData.count == MemoryLayout<UInt32>.size else {
      throw StoreError.invalidFile("Native Messaging 长度前缀不完整")
    }

    let length = lengthData.withUnsafeBytes { bytes in
      UInt32(littleEndian: bytes.loadUnaligned(as: UInt32.self))
    }
    guard length <= PagecaseSchema.nativeMessageLimit else {
      throw StoreError.messageTooLarge(Int(length))
    }

    var payload = Data()
    while payload.count < Int(length) {
      let remaining = Int(length) - payload.count
      let chunk = try handle.read(upToCount: remaining) ?? Data()
      guard !chunk.isEmpty else {
        throw StoreError.invalidFile("Native Messaging 消息正文不完整")
      }
      payload.append(chunk)
    }
    return try PagecaseJSON.makeDecoder().decode(type, from: payload)
  }
}
