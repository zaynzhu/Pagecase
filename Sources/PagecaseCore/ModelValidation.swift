import Foundation

public enum PagecaseValidator {
  public static func validate(_ state: LiveState) throws {
    guard state.schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(state.schemaVersion)
    }
    try validateIdentifier(state.source.id, field: "来源标识")
    guard state.source.kind == "chrome" else {
      throw StoreError.invalidFile("来源类型必须是 chrome")
    }
    try validate(windows: state.windows)
  }

  public static func validate(_ snapshot: SavedSnapshot) throws {
    guard snapshot.schemaVersion == PagecaseSchema.currentVersion else {
      throw StoreError.unsupportedSchema(snapshot.schemaVersion)
    }
    try validateIdentifier(snapshot.id, field: "快照标识")
    try validateIdentifier(snapshot.sourceId, field: "来源标识")
    guard !snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw StoreError.invalidFile("快照名称不能为空")
    }
    try validate(windows: snapshot.windows)
  }

  private static func validate(windows: [BrowserWindow]) throws {
    var windowIds = Set<Int>()
    var windowOrders = Set<Int>()
    var groupIds = Set<Int>()
    var pageIds = Set<Int>()

    for window in windows {
      guard windowIds.insert(window.id).inserted else {
        throw StoreError.invalidFile("窗口标识重复：\(window.id)")
      }
      guard window.order >= 0, windowOrders.insert(window.order).inserted else {
        throw StoreError.invalidFile("窗口顺序无效：\(window.order)")
      }

      var groupOrders = Set<Int>()
      for group in window.groups {
        guard groupIds.insert(group.id).inserted else {
          throw StoreError.invalidFile("标签组标识重复：\(group.id)")
        }
        guard group.order >= 0, groupOrders.insert(group.order).inserted else {
          throw StoreError.invalidFile("标签组顺序无效：\(group.order)")
        }
        for page in group.tabs {
          try validate(
            page,
            expectedWindowId: window.id,
            expectedGroupId: group.id,
            pageIds: &pageIds
          )
        }
      }

      for page in window.ungroupedTabs {
        try validate(
          page,
          expectedWindowId: window.id,
          expectedGroupId: nil,
          pageIds: &pageIds
        )
      }
    }
  }

  private static func validate(
    _ page: PageItem,
    expectedWindowId: Int,
    expectedGroupId: Int?,
    pageIds: inout Set<Int>
  ) throws {
    guard pageIds.insert(page.id).inserted else {
      throw StoreError.invalidFile("网页标识重复：\(page.id)")
    }
    guard page.windowId == expectedWindowId else {
      throw StoreError.invalidFile("网页 \(page.id) 的窗口标识不一致")
    }
    guard page.groupId == expectedGroupId else {
      throw StoreError.invalidFile("网页 \(page.id) 的标签组标识不一致")
    }
    guard page.index >= 0 else {
      throw StoreError.invalidFile("网页 \(page.id) 的顺序无效")
    }
    guard isWebURL(page.url) else {
      throw StoreError.invalidFile("网页 \(page.id) 不是有效的 http/https 地址")
    }
  }

  private static func validateIdentifier(_ value: String, field: String) throws {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    guard !value.isEmpty,
          value.utf8.count <= 128,
          value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      throw StoreError.invalidFile("\(field)无效")
    }
  }

  private static func isWebURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(),
          let host = components.host,
          !host.isEmpty else {
      return false
    }
    return scheme == "http" || scheme == "https"
  }
}
