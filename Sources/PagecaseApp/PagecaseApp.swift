import SwiftUI

@main
struct PagecaseApp: App {
  @StateObject private var model = AppModel.make()

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        .frame(minWidth: 860, minHeight: 560)
        .preferredColorScheme(qaColorScheme)
    }
    .defaultSize(width: 1080, height: 700)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(after: .sidebar) {
        Button("搜索") {
          model.requestSearchFocus()
        }
        .keyboardShortcut("k", modifiers: .command)
      }
    }
  }

  private var qaColorScheme: ColorScheme? {
    switch ProcessInfo.processInfo.environment["PAGECASE_APPEARANCE"] {
    case "light":
      return .light
    case "dark":
      return .dark
    default:
      return nil
    }
  }
}
