import Foundation

public enum ChromeGroupColor: String, Codable, CaseIterable, Sendable {
  case grey
  case blue
  case red
  case yellow
  case green
  case pink
  case purple
  case cyan
  case orange
}

public struct BrowserSource: Codable, Equatable, Sendable {
  public let id: String
  public let kind: String
  public var label: String
  public let capturedAt: Date

  public init(id: String, kind: String = "chrome", label: String, capturedAt: Date) {
    self.id = id
    self.kind = kind
    self.label = label
    self.capturedAt = capturedAt
  }

  public func isFresh(at date: Date = Date()) -> Bool {
    date.timeIntervalSince(capturedAt) <= PagecaseSchema.sourceFreshnessInterval
  }
}

public struct PageItem: Codable, Equatable, Identifiable, Sendable {
  public let id: Int
  public let windowId: Int
  public let groupId: Int?
  public let index: Int
  public let title: String
  public let url: String
  public let pinned: Bool
  public let active: Bool
  public let audible: Bool
  public let discarded: Bool

  public init(
    id: Int,
    windowId: Int,
    groupId: Int?,
    index: Int,
    title: String,
    url: String,
    pinned: Bool = false,
    active: Bool = false,
    audible: Bool = false,
    discarded: Bool = false
  ) {
    self.id = id
    self.windowId = windowId
    self.groupId = groupId
    self.index = index
    self.title = title
    self.url = url
    self.pinned = pinned
    self.active = active
    self.audible = audible
    self.discarded = discarded
  }

  public var displayTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? domain : trimmedTitle
  }

  public var domain: String {
    guard let host = URL(string: url)?.host, !host.isEmpty else {
      return url
    }

    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}

public struct TabGroup: Codable, Equatable, Identifiable, Sendable {
  public let id: Int
  public let title: String
  public let color: ChromeGroupColor
  public let collapsed: Bool
  public let order: Int
  public let tabs: [PageItem]

  public init(
    id: Int,
    title: String,
    color: ChromeGroupColor,
    collapsed: Bool,
    order: Int,
    tabs: [PageItem]
  ) {
    self.id = id
    self.title = title
    self.color = color
    self.collapsed = collapsed
    self.order = order
    self.tabs = tabs
  }

  public var displayTitle: String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "未命名标签组" : trimmedTitle
  }
}

public struct BrowserWindow: Codable, Equatable, Identifiable, Sendable {
  public let id: Int
  public let order: Int
  public let focused: Bool
  public let groups: [TabGroup]
  public let ungroupedTabs: [PageItem]

  public init(
    id: Int,
    order: Int,
    focused: Bool,
    groups: [TabGroup],
    ungroupedTabs: [PageItem]
  ) {
    self.id = id
    self.order = order
    self.focused = focused
    self.groups = groups
    self.ungroupedTabs = ungroupedTabs
  }

  public var tabCount: Int {
    groups.reduce(ungroupedTabs.count) { $0 + $1.tabs.count }
  }
}

public struct LiveState: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let source: BrowserSource
  public let windows: [BrowserWindow]

  public init(schemaVersion: Int = 1, source: BrowserSource, windows: [BrowserWindow]) {
    self.schemaVersion = schemaVersion
    self.source = source
    self.windows = windows
  }

  public var tabCount: Int {
    windows.reduce(0) { $0 + $1.tabCount }
  }

  public var groupCount: Int {
    windows.reduce(0) { $0 + $1.groups.count }
  }
}

public struct SavedSnapshot: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: String
  public var name: String
  public let createdAt: Date
  public var updatedAt: Date
  public let sourceId: String
  public let windows: [BrowserWindow]

  public init(
    schemaVersion: Int = 1,
    id: String = UUID().uuidString.lowercased(),
    name: String,
    createdAt: Date = Date(),
    updatedAt: Date? = nil,
    sourceId: String,
    windows: [BrowserWindow]
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
    self.sourceId = sourceId
    self.windows = windows
  }

  public var tabCount: Int {
    windows.reduce(0) { $0 + $1.tabCount }
  }

  public var groupCount: Int {
    windows.reduce(0) { $0 + $1.groups.count }
  }
}

public struct LibraryExport: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let exportedAt: Date
  public let applicationVersion: String
  public let snapshots: [SavedSnapshot]

  public init(
    schemaVersion: Int = 1,
    exportedAt: Date = Date(),
    applicationVersion: String,
    snapshots: [SavedSnapshot]
  ) {
    self.schemaVersion = schemaVersion
    self.exportedAt = exportedAt
    self.applicationVersion = applicationVersion
    self.snapshots = snapshots
  }
}

public enum PagecaseSchema {
  public static let currentVersion = 1
  public static let nativeMessageLimit = 4 * 1024 * 1024
  public static let sourceFreshnessInterval: TimeInterval = 30
}
