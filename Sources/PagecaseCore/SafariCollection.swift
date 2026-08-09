import Foundation

public struct SafariCapturedPage: Equatable, Sendable {
  public let title: String
  public let url: String
  public let index: Int
  public let active: Bool

  public init(title: String, url: String, index: Int, active: Bool = false) {
    self.title = title
    self.url = url
    self.index = index
    self.active = active
  }
}

public struct SafariCapture: Equatable, Sendable {
  public let capturedAt: Date
  public let pages: [SafariCapturedPage]
  public let skippedPageCount: Int

  public init(
    capturedAt: Date = Date(),
    pages: [SafariCapturedPage],
    skippedPageCount: Int = 0
  ) {
    self.capturedAt = capturedAt
    self.pages = pages
    self.skippedPageCount = skippedPageCount
  }
}

public enum SafariCollectionBuilder {
  public static let sourceId = "safari-on-demand"
  public static let sourceLabel = "Safari · 按需收纳"

  public static func makeSnapshot(
    from capture: SafariCapture,
    name: String
  ) throws -> SavedSnapshot {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw StoreError.invalidFile("合集名称不能为空")
    }
    guard !capture.pages.isEmpty else {
      throw StoreError.invalidFile("Safari 当前窗口没有可保存的网页")
    }

    let windowId = 1
    let pages = capture.pages.enumerated().map { offset, capturedPage in
      PageItem(
        id: offset + 1,
        windowId: windowId,
        groupId: nil,
        index: capturedPage.index,
        title: capturedPage.title,
        url: capturedPage.url,
        active: capturedPage.active
      )
    }
    let window = BrowserWindow(
      id: windowId,
      order: 0,
      focused: true,
      groups: [],
      ungroupedTabs: pages
    )

    return SavedSnapshot(
      name: trimmedName,
      createdAt: capture.capturedAt,
      sourceId: sourceId,
      sourceKind: .safari,
      sourceLabel: sourceLabel,
      scope: .collection,
      windows: [window]
    )
  }
}
