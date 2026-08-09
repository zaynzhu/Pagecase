import Foundation

public enum SearchResultKind: String, Codable, Sendable {
  case live
  case snapshot
}

public enum SearchResultTarget: String, Codable, Sendable {
  case page
  case group
}

public struct SearchResult: Identifiable, Equatable, Sendable {
  public let id: String
  public let kind: SearchResultKind
  public let target: SearchResultTarget
  public let title: String
  public let url: String?
  public let domain: String?
  public let sourceId: String
  public let sourceKind: BrowserKind
  public let sourceLabel: String
  public let context: String
  public let capturedAt: Date
  public let tabId: Int?
  public let windowId: Int?
  public let snapshotId: String?
  public let groupId: Int?
  public let pageCount: Int?

  public init(
    id: String,
    kind: SearchResultKind,
    target: SearchResultTarget,
    title: String,
    url: String?,
    domain: String?,
    sourceId: String,
    sourceKind: BrowserKind,
    sourceLabel: String,
    context: String,
    capturedAt: Date,
    tabId: Int?,
    windowId: Int?,
    snapshotId: String?,
    groupId: Int?,
    pageCount: Int?
  ) {
    self.id = id
    self.kind = kind
    self.target = target
    self.title = title
    self.url = url
    self.domain = domain
    self.sourceId = sourceId
    self.sourceKind = sourceKind
    self.sourceLabel = sourceLabel
    self.context = context
    self.capturedAt = capturedAt
    self.tabId = tabId
    self.windowId = windowId
    self.snapshotId = snapshotId
    self.groupId = groupId
    self.pageCount = pageCount
  }
}

public enum SearchEngine {
  public static func search(
    query: String,
    liveStates: [LiveState],
    snapshots: [SavedSnapshot],
    sourceLabels: [String: String] = [:]
  ) -> [SearchResult] {
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else {
      return []
    }

    var scored: [(score: Int, result: SearchResult)] = []

    for state in liveStates {
      let sourceLabel = sourceLabels[state.source.id] ?? state.source.label
      appendItems(
        windows: state.windows,
        sourceId: state.source.id,
        sourceKind: state.source.kind,
        sourceLabel: sourceLabel,
        containerId: "live",
        containerName: nil,
        capturedAt: state.source.capturedAt,
        kind: .live,
        normalizedQuery: normalizedQuery,
        into: &scored
      )
    }

    for snapshot in snapshots {
      let sourceLabel = sourceLabels[snapshot.sourceId] ?? snapshot.sourceLabel
      appendItems(
        windows: snapshot.windows,
        sourceId: snapshot.sourceId,
        sourceKind: snapshot.sourceKind,
        sourceLabel: sourceLabel,
        containerId: snapshot.id,
        containerName: snapshot.name,
        capturedAt: snapshot.createdAt,
        kind: .snapshot,
        normalizedQuery: normalizedQuery,
        into: &scored
      )
    }

    return scored.sorted {
      if $0.score != $1.score {
        return $0.score > $1.score
      }
      if $0.result.kind != $1.result.kind {
        return $0.result.kind == .live
      }
      return $0.result.capturedAt > $1.result.capturedAt
    }.map(\.result)
  }

  private static func appendItems(
    windows: [BrowserWindow],
    sourceId: String,
    sourceKind: BrowserKind,
    sourceLabel: String,
    containerId: String,
    containerName: String?,
    capturedAt: Date,
    kind: SearchResultKind,
    normalizedQuery: String,
    into scored: inout [(score: Int, result: SearchResult)]
  ) {
    for window in windows {
      for group in window.groups {
        appendGroup(
          group: group,
          window: window,
          sourceId: sourceId,
          sourceKind: sourceKind,
          sourceLabel: sourceLabel,
          containerId: containerId,
          containerName: containerName,
          capturedAt: capturedAt,
          kind: kind,
          normalizedQuery: normalizedQuery,
          into: &scored
        )

        for page in group.tabs {
          append(
            page: page,
            groupName: group.displayTitle,
            windowOrder: window.order,
            sourceId: sourceId,
            sourceKind: sourceKind,
            sourceLabel: sourceLabel,
            containerId: containerId,
            containerName: containerName,
            capturedAt: capturedAt,
            kind: kind,
            normalizedQuery: normalizedQuery,
            into: &scored
          )
        }
      }

      for page in window.ungroupedTabs {
        append(
          page: page,
          groupName: "未分组",
          windowOrder: window.order,
          sourceId: sourceId,
          sourceKind: sourceKind,
          sourceLabel: sourceLabel,
          containerId: containerId,
          containerName: containerName,
          capturedAt: capturedAt,
          kind: kind,
          normalizedQuery: normalizedQuery,
          into: &scored
        )
      }
    }
  }

  private static func appendGroup(
    group: TabGroup,
    window: BrowserWindow,
    sourceId: String,
    sourceKind: BrowserKind,
    sourceLabel: String,
    containerId: String,
    containerName: String?,
    capturedAt: Date,
    kind: SearchResultKind,
    normalizedQuery: String,
    into scored: inout [(score: Int, result: SearchResult)]
  ) {
    let normalizedTitle = normalize(group.displayTitle)
    let score: Int
    if normalizedTitle == normalizedQuery {
      score = 800
    } else if normalizedTitle.hasPrefix(normalizedQuery) {
      score = 750
    } else if normalizedTitle.contains(normalizedQuery) {
      score = 700
    } else {
      return
    }

    let contextParts = [containerName, "窗口 \(window.order + 1)"].compactMap { $0 }
    let identityPrefix = kind == .live ? "live" : "snapshot"
    let result = SearchResult(
      id: "\(identityPrefix)-group-\(sourceId)-\(containerId)-\(window.id)-\(group.id)",
      kind: kind,
      target: .group,
      title: group.displayTitle,
      url: nil,
      domain: nil,
      sourceId: sourceId,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
      context: contextParts.joined(separator: " › "),
      capturedAt: capturedAt,
      tabId: nil,
      windowId: window.id,
      snapshotId: kind == .snapshot ? containerId : nil,
      groupId: group.id,
      pageCount: group.tabs.count
    )
    scored.append((score, result))
  }

  private static func append(
    page: PageItem,
    groupName: String,
    windowOrder: Int,
    sourceId: String,
    sourceKind: BrowserKind,
    sourceLabel: String,
    containerId: String,
    containerName: String?,
    capturedAt: Date,
    kind: SearchResultKind,
    normalizedQuery: String,
    into scored: inout [(score: Int, result: SearchResult)]
  ) {
    guard let score = matchScore(
      query: normalizedQuery,
      title: page.displayTitle,
      group: groupName,
      container: containerName,
      domain: page.domain,
      url: page.url
    ) else {
      return
    }

    let contextParts = [containerName, "窗口 \(windowOrder + 1)", groupName].compactMap { $0 }
    let identityPrefix = kind == .live ? "live" : "snapshot"
    let result = SearchResult(
      id: "\(identityPrefix)-\(sourceId)-\(containerId)-\(windowOrder)-\(page.id)-\(page.index)",
      kind: kind,
      target: .page,
      title: page.displayTitle,
      url: page.url,
      domain: page.domain,
      sourceId: sourceId,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
      context: contextParts.joined(separator: " › "),
      capturedAt: capturedAt,
      tabId: kind == .live ? page.id : nil,
      windowId: kind == .live ? page.windowId : nil,
      snapshotId: kind == .snapshot ? containerId : nil,
      groupId: nil,
      pageCount: nil
    )
    scored.append((score, result))
  }

  private static func matchScore(
    query: String,
    title: String,
    group: String,
    container: String?,
    domain: String,
    url: String
  ) -> Int? {
    let normalizedTitle = normalize(title)
    if normalizedTitle.hasPrefix(query) {
      return 600
    }
    if normalizedTitle.contains(query) {
      return 500
    }
    if normalize(group).contains(query) || normalize(container ?? "").contains(query) {
      return 400
    }
    if normalize(domain).contains(query) {
      return 300
    }
    if normalize(url).contains(query) {
      return 200
    }
    return nil
  }

  private static func normalize(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
