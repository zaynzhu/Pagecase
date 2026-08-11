import Foundation

/// 当前仍在 Chrome 中、且已经完整写入本地快照的标签组。
/// 这只是给用户的手动关闭清单，不携带任何关闭或修改浏览器的命令。
public struct ChromeClosableGroupCandidate: Identifiable, Equatable, Sendable {
  public let sourceId: String
  public let sourceLabel: String
  public let windowId: Int
  public let windowOrder: Int
  public let group: TabGroup
  public let snapshotId: String
  public let snapshotName: String
  public let snapshotCreatedAt: Date

  public init(
    sourceId: String,
    sourceLabel: String,
    windowId: Int,
    windowOrder: Int,
    group: TabGroup,
    snapshotId: String,
    snapshotName: String,
    snapshotCreatedAt: Date
  ) {
    self.sourceId = sourceId
    self.sourceLabel = sourceLabel
    self.windowId = windowId
    self.windowOrder = windowOrder
    self.group = group
    self.snapshotId = snapshotId
    self.snapshotName = snapshotName
    self.snapshotCreatedAt = snapshotCreatedAt
  }

  public var id: String {
    "\(sourceId):\(windowId):\(group.id):\(snapshotId)"
  }

  public var pageCount: Int {
    group.tabs.count
  }
}

public enum ChromeClosableGroupBuilder {
  public static func make(
    liveStates: [LiveState],
    snapshots: [SavedSnapshot],
    at date: Date = Date()
  ) -> [ChromeClosableGroupCandidate] {
    liveStates
      .filter {
        $0.source.kind == .chrome && $0.source.isFresh(at: date)
      }
      .flatMap { state in
        state.windows.flatMap { window in
          window.groups.compactMap { group -> ChromeClosableGroupCandidate? in
            guard !group.tabs.isEmpty else {
              return nil
            }

            let coverage = SnapshotCoverageEvaluator.evaluate(
              group: group,
              sourceId: state.source.id,
              snapshots: snapshots
            )
            guard coverage.isComplete, let snapshot = coverage.snapshot else {
              return nil
            }

            return ChromeClosableGroupCandidate(
              sourceId: state.source.id,
              sourceLabel: state.source.label,
              windowId: window.id,
              windowOrder: window.order,
              group: group,
              snapshotId: snapshot.id,
              snapshotName: snapshot.name,
              snapshotCreatedAt: snapshot.createdAt
            )
          }
        }
      }
      .sorted { left, right in
        if left.sourceLabel != right.sourceLabel {
          return left.sourceLabel < right.sourceLabel
        }
        if left.windowOrder != right.windowOrder {
          return left.windowOrder < right.windowOrder
        }
        if left.group.order != right.group.order {
          return left.group.order < right.group.order
        }
        return left.id < right.id
      }
  }
}
