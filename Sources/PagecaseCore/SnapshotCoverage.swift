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

public struct GroupSnapshotCoverage: Equatable, Sendable {
  public let snapshot: SavedSnapshot?
  public let pageCount: Int
  public let uncoveredPageCount: Int

  public init(
    snapshot: SavedSnapshot?,
    pageCount: Int,
    uncoveredPageCount: Int
  ) {
    self.snapshot = snapshot
    self.pageCount = pageCount
    self.uncoveredPageCount = uncoveredPageCount
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
          uncoveredPageCount: uncoveredItemCount(
            liveItems: liveKeys,
            savedItems: backupKeys(in: snapshot.windows)
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

  public static func evaluate(
    group: TabGroup,
    sourceId: String,
    snapshots: [SavedSnapshot]
  ) -> GroupSnapshotCoverage {
    let liveURLs = group.tabs.map(\.url)
    let candidates = snapshots
      .filter { $0.sourceId == sourceId }
      .flatMap { snapshot in
        snapshot.windows.flatMap { window in
          window.groups
            .filter {
              $0.displayTitle == group.displayTitle
                && $0.color == group.color
            }
            .map { candidateGroup in
              (
                snapshot: snapshot,
                uncoveredPageCount: uncoveredItemCount(
                  liveItems: liveURLs,
                  savedItems: candidateGroup.tabs.map(\.url)
                )
              )
            }
        }
      }

    guard let best = candidates.min(by: { left, right in
      if left.uncoveredPageCount != right.uncoveredPageCount {
        return left.uncoveredPageCount < right.uncoveredPageCount
      }
      return left.snapshot.createdAt > right.snapshot.createdAt
    }) else {
      return GroupSnapshotCoverage(
        snapshot: nil,
        pageCount: liveURLs.count,
        uncoveredPageCount: liveURLs.count
      )
    }

    return GroupSnapshotCoverage(
      snapshot: best.snapshot,
      pageCount: liveURLs.count,
      uncoveredPageCount: best.uncoveredPageCount
    )
  }

  private static func uncoveredItemCount<Item: Hashable>(
    liveItems: [Item],
    savedItems: [Item]
  ) -> Int {
    var available = Dictionary(grouping: savedItems, by: { $0 })
      .mapValues(\.count)
    var uncovered = 0

    for item in liveItems {
      guard let count = available[item], count > 0 else {
        uncovered += 1
        continue
      }
      available[item] = count - 1
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
