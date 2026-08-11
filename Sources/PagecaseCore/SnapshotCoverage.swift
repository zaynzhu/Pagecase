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
  public let windowId: Int?
  public let groupId: Int?
  public let pageCount: Int
  public let uncoveredPageCount: Int

  public init(
    snapshot: SavedSnapshot?,
    windowId: Int? = nil,
    groupId: Int? = nil,
    pageCount: Int,
    uncoveredPageCount: Int
  ) {
    self.snapshot = snapshot
    self.windowId = windowId
    self.groupId = groupId
    self.pageCount = pageCount
    self.uncoveredPageCount = uncoveredPageCount
  }

  public var isComplete: Bool {
    snapshot != nil && uncoveredPageCount == 0
  }
}

public enum ChromeSnapshotPresenceState: Equatable, Sendable {
  case allOpen
  case partiallyOpen
  case noneOpen
  case unavailable
}

public struct ChromeSnapshotPresence: Equatable, Sendable {
  public let state: ChromeSnapshotPresenceState
  public let snapshotPageCount: Int
  public let openPageCount: Int

  public init(
    state: ChromeSnapshotPresenceState,
    snapshotPageCount: Int,
    openPageCount: Int
  ) {
    self.state = state
    self.snapshotPageCount = snapshotPageCount
    self.openPageCount = openPageCount
  }

  public var closedPageCount: Int {
    max(snapshotPageCount - openPageCount, 0)
  }
}

public enum SnapshotPresenceEvaluator {
  public static func evaluate(
    snapshot: SavedSnapshot,
    liveStates: [LiveState],
    at date: Date = Date()
  ) -> ChromeSnapshotPresence? {
    let snapshotPages = pages(in: snapshot.windows)
    guard snapshot.sourceKind == .chrome, !snapshotPages.isEmpty else {
      return nil
    }
    return evaluate(
      pages: snapshotPages,
      sourceId: snapshot.sourceId,
      liveStates: liveStates,
      at: date
    )
  }

  public static func evaluate(
    group: TabGroup,
    sourceId: String,
    liveStates: [LiveState],
    at date: Date = Date()
  ) -> ChromeSnapshotPresence {
    guard let liveState = availableChromeState(
      sourceId: sourceId,
      liveStates: liveStates,
      at: date
    ) else {
      return unavailablePresence(pageCount: group.tabs.count)
    }
    guard let liveGroup = liveState.windows
      .flatMap(\.groups)
      .first(where: { $0.id == group.id }) else {
      return ChromeSnapshotPresence(
        state: .noneOpen,
        snapshotPageCount: group.tabs.count,
        openPageCount: 0
      )
    }
    return presence(
      expectedPages: group.tabs,
      availablePages: liveGroup.tabs
    )
  }

  public static func evaluate(
    pages snapshotPages: [PageItem],
    sourceId: String,
    liveStates: [LiveState],
    at date: Date = Date()
  ) -> ChromeSnapshotPresence {
    guard let liveState = availableChromeState(
      sourceId: sourceId,
      liveStates: liveStates,
      at: date
    ) else {
      return unavailablePresence(pageCount: snapshotPages.count)
    }

    return presence(
      expectedPages: snapshotPages,
      availablePages: pages(in: liveState.windows)
    )
  }

  private static func presence(
    expectedPages: [PageItem],
    availablePages: [PageItem]
  ) -> ChromeSnapshotPresence {
    let openPageCount = matchedItemCount(
      expectedItems: expectedPages.map(\.url),
      availableItems: availablePages.map(\.url)
    )
    let state: ChromeSnapshotPresenceState
    if openPageCount == 0 {
      state = .noneOpen
    } else if openPageCount == expectedPages.count {
      state = .allOpen
    } else {
      state = .partiallyOpen
    }

    return ChromeSnapshotPresence(
      state: state,
      snapshotPageCount: expectedPages.count,
      openPageCount: openPageCount
    )
  }

  private static func availableChromeState(
    sourceId: String,
    liveStates: [LiveState],
    at date: Date
  ) -> LiveState? {
    liveStates.first(where: {
      $0.source.id == sourceId
        && $0.source.kind == .chrome
        && $0.source.isFresh(at: date)
    })
  }

  private static func unavailablePresence(pageCount: Int) -> ChromeSnapshotPresence {
    ChromeSnapshotPresence(
      state: .unavailable,
      snapshotPageCount: pageCount,
      openPageCount: 0
    )
  }

  private static func matchedItemCount<Item: Hashable>(
    expectedItems: [Item],
    availableItems: [Item]
  ) -> Int {
    var available = Dictionary(grouping: availableItems, by: { $0 })
      .mapValues(\.count)
    var matched = 0

    for item in expectedItems {
      guard let count = available[item], count > 0 else {
        continue
      }
      available[item] = count - 1
      matched += 1
    }

    return matched
  }

  private static func pages(in windows: [BrowserWindow]) -> [PageItem] {
    windows.flatMap { window in
      window.groups.flatMap(\.tabs) + window.ungroupedTabs
    }
  }
}

public enum SnapshotCoverageEvaluator {
  public static func evaluate(
    liveState: LiveState,
    snapshots: [SavedSnapshot]
  ) -> SnapshotCoverage {
    let liveKeys = backupKeys(in: liveState.windows)
    let candidates = snapshots
      .filter {
        $0.sourceKind == liveState.source.kind
          && $0.sourceId == liveState.source.id
          && $0.scope == .fullState
      }
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
      .filter { $0.sourceKind == .chrome && $0.sourceId == sourceId }
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
                windowId: window.id,
                groupId: candidateGroup.id,
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
        windowId: nil,
        groupId: nil,
        pageCount: liveURLs.count,
        uncoveredPageCount: liveURLs.count
      )
    }

    return GroupSnapshotCoverage(
      snapshot: best.snapshot,
      windowId: best.windowId,
      groupId: best.groupId,
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
