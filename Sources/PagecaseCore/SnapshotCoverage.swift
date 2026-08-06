import Foundation

public struct SnapshotCoverage: Equatable, Sendable {
  public let snapshot: SavedSnapshot?
  public let livePageCount: Int
  public let uncoveredPageCount: Int

  public init(
    snapshot: SavedSnapshot?,
    livePageCount: Int,
    uncoveredPageCount: Int
  ) {
    self.snapshot = snapshot
    self.livePageCount = livePageCount
    self.uncoveredPageCount = uncoveredPageCount
  }

  public var coveredPageCount: Int {
    max(livePageCount - uncoveredPageCount, 0)
  }

  public var isComplete: Bool {
    snapshot != nil && uncoveredPageCount == 0
  }
}

public enum SnapshotCoverageEvaluator {
  public static func evaluate(
    liveState: LiveState,
    snapshots: [SavedSnapshot]
  ) -> SnapshotCoverage {
    let liveKeys = backupKeys(in: liveState.windows)
    let candidates = snapshots
      .filter { $0.sourceId == liveState.source.id }
      .map { snapshot in
        (
          snapshot: snapshot,
          uncoveredPageCount: uncoveredPageCount(
            liveKeys: liveKeys,
            snapshotKeys: backupKeys(in: snapshot.windows)
          )
        )
      }

    guard let best = candidates.min(by: { left, right in
      if left.uncoveredPageCount != right.uncoveredPageCount {
        return left.uncoveredPageCount < right.uncoveredPageCount
      }
      return left.snapshot.createdAt > right.snapshot.createdAt
    }) else {
      return SnapshotCoverage(
        snapshot: nil,
        livePageCount: liveKeys.count,
        uncoveredPageCount: liveKeys.count
      )
    }

    return SnapshotCoverage(
      snapshot: best.snapshot,
      livePageCount: liveKeys.count,
      uncoveredPageCount: best.uncoveredPageCount
    )
  }

  private static func uncoveredPageCount(
    liveKeys: [BackupKey],
    snapshotKeys: [BackupKey]
  ) -> Int {
    var available = Dictionary(grouping: snapshotKeys, by: { $0 })
      .mapValues(\.count)
    var uncovered = 0

    for key in liveKeys {
      guard let count = available[key], count > 0 else {
        uncovered += 1
        continue
      }
      available[key] = count - 1
    }

    return uncovered
  }

  private static func backupKeys(in windows: [BrowserWindow]) -> [BackupKey] {
    windows.flatMap { window in
      let grouped = window.groups.flatMap { group in
        group.tabs.map { page in
          BackupKey(
            url: page.url,
            groupTitle: group.displayTitle,
            groupColor: group.color.rawValue
          )
        }
      }
      let ungrouped = window.ungroupedTabs.map { page in
        BackupKey(url: page.url, groupTitle: nil, groupColor: nil)
      }
      return grouped + ungrouped
    }
  }
}

private struct BackupKey: Hashable {
  let url: String
  let groupTitle: String?
  let groupColor: String?
}
