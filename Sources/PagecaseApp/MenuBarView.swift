import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var model: AppModel
  let mainWindowId: String

  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(sourceSummary)
    Text("\(model.totalLiveTabs) 个实时网页 · \(model.snapshots.count) 个快照")

    Divider()

    Button("打开页匣") {
      showMainWindow(focusSearch: false)
    }

    Button("搜索网页…") {
      showMainWindow(focusSearch: true)
    }
    .keyboardShortcut("k", modifiers: [.command, .shift])

    Divider()

    Button("退出页匣") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }

  private var sourceSummary: String {
    if model.isDemoMode {
      return "演示模式"
    }
    if model.connectedSourceCount > 0, model.staleSourceCount > 0 {
      return "\(model.connectedSourceCount) 个已连接 · \(model.staleSourceCount) 个过期"
    }
    if model.connectedSourceCount > 0 {
      return "\(model.connectedSourceCount) 个来源已连接"
    }
    if model.staleSourceCount > 0 {
      return "\(model.staleSourceCount) 个来源数据过期"
    }
    return "等待 Chrome"
  }

  private func showMainWindow(focusSearch: Bool) {
    model.refresh(force: true)
    if focusSearch {
      model.requestSearchFocus()
    }
    openWindow(id: mainWindowId)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
