import Foundation

public struct GroupRestorePreview: Equatable, Sendable {
  public let pageCount: Int
  public let alreadyOpenPageCount: Int

  public init(pageCount: Int, alreadyOpenPageCount: Int) {
    self.pageCount = pageCount
    self.alreadyOpenPageCount = alreadyOpenPageCount
  }
}

public enum GroupRestorePreviewBuilder {
  public static func make(
    group: TabGroup,
    sourceId: String,
    liveStates: [LiveState]
  ) -> GroupRestorePreview {
    guard let state = liveStates.first(where: {
      $0.source.id == sourceId && $0.source.kind == .chrome
    }) else {
      return GroupRestorePreview(
        pageCount: group.tabs.count,
        alreadyOpenPageCount: 0
      )
    }

    var openURLCounts: [String: Int] = [:]
    for window in state.windows {
      for page in window.groups.flatMap(\.tabs) + window.ungroupedTabs {
        openURLCounts[page.url, default: 0] += 1
      }
    }

    var alreadyOpenPageCount = 0
    for page in group.tabs {
      guard let openCount = openURLCounts[page.url], openCount > 0 else {
        continue
      }
      alreadyOpenPageCount += 1
      openURLCounts[page.url] = openCount - 1
    }

    return GroupRestorePreview(
      pageCount: group.tabs.count,
      alreadyOpenPageCount: alreadyOpenPageCount
    )
  }
}
