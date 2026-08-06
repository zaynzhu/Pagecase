import Darwin
import Foundation
import PagecaseCore

final class BridgeRuntime: @unchecked Sendable {
  private let paths: AppPaths
  private let snapshots: SnapshotRepository
  private let commands: CommandRepository
  private let output = FileHandle.standardOutput
  private let outputLock = NSLock()
  private let stateLock = NSLock()
  private let watchQueue = DispatchQueue(label: "com.zaynzhu.pagecase.bridge.commands")

  private var activeSourceId: String?
  private var directoryDescriptor: Int32 = -1
  private var directorySource: DispatchSourceFileSystemObject?

  init(paths: AppPaths) throws {
    self.paths = paths
    snapshots = try SnapshotRepository(paths: paths)
    commands = try CommandRepository(paths: paths)
  }

  func run() throws {
    startCommandWatcher()
    defer {
      directorySource?.cancel()
    }

    while let message = try NativeMessageFramer.readMessage(
      NativeInboundMessage.self,
      from: .standardInput
    ) {
      try handle(message)
    }
  }

  private func handle(_ message: NativeInboundMessage) throws {
    switch message.type {
    case "snapshot":
      guard let state = message.payload else {
        throw StoreError.invalidFile("snapshot 消息缺少 payload")
      }
      try snapshots.saveLiveState(state)
      setActiveSourceId(state.source.id)
      flushCommands()
    case "commandResult":
      guard let commandId = message.commandId,
            let sourceId = message.sourceId,
            let success = message.success,
            let resultMessage = message.message else {
        throw StoreError.invalidFile("commandResult 消息参数不完整")
      }
      try commands.saveResult(
        BrowserCommandResult(
          id: commandId,
          sourceId: sourceId,
          success: success,
          message: resultMessage
        )
      )
    case "ping":
      try send(NativeOutboundMessage(type: "pong"))
    default:
      writeError("忽略未知消息类型：\(message.type)")
    }
  }

  private func startCommandWatcher() {
    directoryDescriptor = Darwin.open(paths.commands.path, O_EVTONLY)
    guard directoryDescriptor >= 0 else {
      writeError("无法监听命令目录：\(paths.commands.path)")
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: directoryDescriptor,
      eventMask: [.write, .extend, .attrib, .rename],
      queue: watchQueue
    )
    source.setEventHandler { [weak self] in
      self?.flushCommands()
    }
    source.setCancelHandler { [directoryDescriptor] in
      Darwin.close(directoryDescriptor)
    }
    directorySource = source
    source.resume()
  }

  private func flushCommands() {
    guard let sourceId = getActiveSourceId() else {
      return
    }

    do {
      let pending = try commands.loadPendingCommands()
        .filter { $0.sourceId == sourceId }

      for command in pending {
        do {
          try commands.claim(command)
          try send(NativeOutboundMessage(command: command))
        } catch {
          writeError("发送命令 \(command.id) 失败：\(error.localizedDescription)")
          try? commands.saveResult(
            BrowserCommandResult(
              id: command.id,
              sourceId: command.sourceId,
              success: false,
              message: "Bridge 发送命令失败"
            )
          )
        }
      }
    } catch {
      writeError("读取命令失败：\(error.localizedDescription)")
    }
  }

  private func send(_ message: NativeOutboundMessage) throws {
    let framed = try NativeMessageFramer.encode(message)
    outputLock.lock()
    defer { outputLock.unlock() }
    try output.write(contentsOf: framed)
  }

  private func setActiveSourceId(_ sourceId: String) {
    stateLock.lock()
    activeSourceId = sourceId
    stateLock.unlock()
  }

  private func getActiveSourceId() -> String? {
    stateLock.lock()
    defer { stateLock.unlock() }
    return activeSourceId
  }

  private func writeError(_ message: String) {
    guard let data = "PagecaseBridge: \(message)\n".data(using: .utf8) else {
      return
    }
    try? FileHandle.standardError.write(contentsOf: data)
  }
}

do {
  let paths = try AppPaths.defaultPaths()
  let runtime = try BridgeRuntime(paths: paths)
  try runtime.run()
} catch {
  let message = "PagecaseBridge: \(error.localizedDescription)\n"
  if let data = message.data(using: .utf8) {
    try? FileHandle.standardError.write(contentsOf: data)
  }
  exit(EXIT_FAILURE)
}
