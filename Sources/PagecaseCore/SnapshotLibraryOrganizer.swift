import Foundation

public struct GroupSnapshotSeries: Identifiable, Equatable, Sendable {
  public let id: String
  public let sourceId: String
  public let windowId: Int
  public let groupId: Int
  public let title: String
  public let color: ChromeGroupColor
  public let snapshots: [SavedSnapshot]

  public var latestSnapshot: SavedSnapshot {
    snapshots[0]
  }
}

public enum SnapshotLibraryItem: Identifiable, Equatable, Sendable {
  case snapshot(SavedSnapshot)
  case groupSeries(GroupSnapshotSeries)

  public var id: String {
    switch self {
    case .snapshot(let snapshot):
      return "snapshot|\(snapshot.id)"
    case .groupSeries(let series):
      return series.id
    }
  }

  fileprivate var latestCreatedAt: Date {
    switch self {
    case .snapshot(let snapshot):
      return snapshot.createdAt
    case .groupSeries(let series):
      return series.latestSnapshot.createdAt
    }
  }
}

public enum SnapshotLibraryOrganizer {
  public static func organize(_ snapshots: [SavedSnapshot]) -> [SnapshotLibraryItem] {
    var standaloneSnapshots: [SavedSnapshot] = []
    var groupSnapshotsByIdentity: [GroupIdentity: [SavedSnapshot]] = [:]

    for snapshot in snapshots {
      guard let identity = groupIdentity(for: snapshot) else {
        standaloneSnapshots.append(snapshot)
        continue
      }
      groupSnapshotsByIdentity[identity, default: []].append(snapshot)
    }

    var items = standaloneSnapshots.map(SnapshotLibraryItem.snapshot)
    for (identity, groupedSnapshots) in groupSnapshotsByIdentity {
      let sortedSnapshots = groupedSnapshots.sorted(by: snapshotComesBefore)
      let series = GroupSnapshotSeries(
        id: identity.id,
        sourceId: identity.sourceId,
        windowId: identity.windowId,
        groupId: identity.groupId,
        title: identity.title,
        color: identity.color,
        snapshots: sortedSnapshots
      )
      items.append(.groupSeries(series))
    }

    return items.sorted {
      if $0.latestCreatedAt != $1.latestCreatedAt {
        return $0.latestCreatedAt > $1.latestCreatedAt
      }
      return $0.id < $1.id
    }
  }

  public static func groupSeries(
    containing snapshotId: String,
    in snapshots: [SavedSnapshot]
  ) -> GroupSnapshotSeries? {
    organize(snapshots).compactMap { item -> GroupSnapshotSeries? in
      guard case .groupSeries(let series) = item else {
        return nil
      }
      return series.snapshots.contains(where: { $0.id == snapshotId }) ? series : nil
    }.first
  }

  private struct GroupIdentity: Hashable {
    let sourceId: String
    let windowId: Int
    let groupId: Int
    let title: String
    let color: ChromeGroupColor

    var id: String {
      "group-series|\(sourceId)|\(windowId)|\(groupId)|\(color.rawValue)|\(title)"
    }
  }

  private static func groupIdentity(for snapshot: SavedSnapshot) -> GroupIdentity? {
    guard snapshot.scope == .group,
          snapshot.windows.count == 1,
          let window = snapshot.windows.first,
          window.groups.count == 1,
          let group = window.groups.first else {
      return nil
    }

    return GroupIdentity(
      sourceId: snapshot.sourceId,
      windowId: window.id,
      groupId: group.id,
      title: group.displayTitle,
      color: group.color
    )
  }

  private static func snapshotComesBefore(
    _ lhs: SavedSnapshot,
    _ rhs: SavedSnapshot
  ) -> Bool {
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt > rhs.createdAt
    }
    return lhs.id < rhs.id
  }
}
