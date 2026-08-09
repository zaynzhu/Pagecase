import Foundation

public enum GroupRestoreReceiptStatus: Equatable, Sendable {
  case success
  case partial
  case failure
  case timeout
}

public struct GroupRestoreReceipt: Equatable, Identifiable, Sendable {
  public let id: String
  public let sourceLabel: String
  public let groupTitle: String
  public let expectedTabCount: Int
  public let createdTabCount: Int?
  public let groupCreated: Bool?
  public let failureStage: BrowserCommandFailureStage?
  public let status: GroupRestoreReceiptStatus
  public let message: String

  public var displayTitle: String {
    let trimmedTitle = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "未命名标签组" : trimmedTitle
  }

  public var title: String {
    switch status {
    case .success:
      return "「\(displayTitle)」已恢复"
    case .partial:
      return "「\(displayTitle)」未完整恢复"
    case .failure:
      return "「\(displayTitle)」恢复失败"
    case .timeout:
      return "「\(displayTitle)」等待确认"
    }
  }

  public var summary: String {
    switch status {
    case .success:
      return "\(expectedTabCount) 个标签已创建并组成标签组"
    case .partial:
      if groupCreated == true || failureStage == .updatingGroup {
        return "\(createdTabCount ?? expectedTabCount) 个标签已成组，组名或颜色尚未确认完成"
      }
      if let createdTabCount {
        return "已确认创建 \(createdTabCount) / \(expectedTabCount) 个标签，尚未完整成组"
      }
      return "Chrome 返回了不完整的恢复结果"
    case .failure:
      return "没有确认创建任何新标签"
    case .timeout:
      return "30 秒内没有收到 Chrome 的最终结果"
    }
  }

  public var guidance: String {
    switch status {
    case .success:
      return "原有标签没有被关闭、移动或重新分组。"
    case .partial:
      return "已创建的标签会保留在 Chrome 中；页匣不会自动清理或重试，请先核对浏览器。"
    case .failure:
      return "请检查 Chrome 连接后再决定是否重试；页匣不会自动创建第二份。"
    case .timeout:
      return "请先检查 Chrome 是否已经出现这些标签；为避免重复创建，页匣不会自动重试。"
    }
  }
}

public enum GroupRestoreReceiptBuilder {
  public static func make(
    command: BrowserCommand,
    sourceLabel: String,
    result: BrowserCommandResult
  ) -> GroupRestoreReceipt? {
    guard command.action == .restoreGroup,
          result.id == command.id,
          result.sourceId == command.sourceId,
          result.action == nil || result.action == .restoreGroup,
          let groupTitle = command.groupTitle,
          let expectedTabCount = command.urls?.count else {
      return nil
    }

    let createdTabCount = result.createdTabCount
      ?? (result.success ? expectedTabCount : nil)
    let groupCreated = result.groupCreated
      ?? (result.success ? true : nil)
    let isComplete = result.success
      && createdTabCount == expectedTabCount
      && groupCreated != false
    let hasPartialChanges = (createdTabCount ?? 0) > 0 || groupCreated == true
    let status: GroupRestoreReceiptStatus
    if isComplete {
      status = .success
    } else if hasPartialChanges || result.success {
      status = .partial
    } else {
      status = .failure
    }

    return GroupRestoreReceipt(
      id: command.id,
      sourceLabel: sourceLabel,
      groupTitle: groupTitle,
      expectedTabCount: expectedTabCount,
      createdTabCount: createdTabCount,
      groupCreated: groupCreated,
      failureStage: result.failureStage,
      status: status,
      message: result.message
    )
  }

  public static func timeout(
    command: BrowserCommand,
    sourceLabel: String
  ) -> GroupRestoreReceipt? {
    guard command.action == .restoreGroup,
          let groupTitle = command.groupTitle,
          let expectedTabCount = command.urls?.count else {
      return nil
    }

    return GroupRestoreReceipt(
      id: command.id,
      sourceLabel: sourceLabel,
      groupTitle: groupTitle,
      expectedTabCount: expectedTabCount,
      createdTabCount: nil,
      groupCreated: nil,
      failureStage: nil,
      status: .timeout,
      message: "Chrome 未及时响应"
    )
  }
}
