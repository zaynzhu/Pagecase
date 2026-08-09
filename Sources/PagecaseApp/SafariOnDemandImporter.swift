import AppKit
import Foundation
import PagecaseCore

protocol SafariCapturing: Sendable {
  func captureCurrentWindow() throws -> SafariCapture
}

enum SafariCaptureError: LocalizedError {
  case notRunning
  case noWindow
  case noWebPages
  case automationDenied
  case scriptFailed(String)

  var errorDescription: String? {
    switch self {
    case .notRunning:
      return "请先打开 Safari，并切换到想收纳的标签组"
    case .noWindow:
      return "Safari 当前没有可以读取的窗口"
    case .noWebPages:
      return "当前 Safari 窗口没有可保存的 http/https 网页"
    case .automationDenied:
      return "页匣没有读取 Safari 的权限，请在系统设置的“隐私与安全性 › 自动化”中允许"
    case .scriptFailed(let message):
      return "读取 Safari 失败：\(message)"
    }
  }
}

struct SystemSafariCapturer: SafariCapturing {
  func captureCurrentWindow() throws -> SafariCapture {
    guard !NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.Safari"
    ).isEmpty else {
      throw SafariCaptureError.notRunning
    }

    var errorInfo: NSDictionary?
    guard let script = NSAppleScript(source: Self.scriptSource) else {
      throw SafariCaptureError.scriptFailed("无法准备读取脚本")
    }
    let descriptor = script.executeAndReturnError(&errorInfo)
    if errorInfo != nil {
      throw mapScriptError(errorInfo)
    }

    var pages: [SafariCapturedPage] = []
    var skippedPageCount = 0
    if descriptor.numberOfItems > 0 {
      for itemIndex in 1...descriptor.numberOfItems {
        guard let item = descriptor.atIndex(itemIndex),
              let title = item.atIndex(1)?.stringValue,
              let url = item.atIndex(2)?.stringValue else {
          skippedPageCount += 1
          continue
        }
        guard Self.isWebURL(url) else {
          skippedPageCount += 1
          continue
        }

        pages.append(
          SafariCapturedPage(
            title: title,
            url: url,
            index: pages.count,
            active: item.atIndex(3)?.booleanValue ?? false
          )
        )
      }
    }

    guard !pages.isEmpty else {
      throw SafariCaptureError.noWebPages
    }
    return SafariCapture(pages: pages, skippedPageCount: skippedPageCount)
  }

  private func mapScriptError(_ errorInfo: NSDictionary?) -> SafariCaptureError {
    let number = (errorInfo?["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
    if number == -1_743 {
      return .automationDenied
    }
    if number == 10_001 {
      return .noWindow
    }
    let message = errorInfo?["NSAppleScriptErrorMessage"] as? String
      ?? "Safari 没有返回可读取的数据"
    return .scriptFailed(message)
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

  private static let scriptSource = """
  tell application "Safari"
    if (count of windows) is 0 then error "Safari 当前没有窗口" number 10001
    set capturedTabs to {}
    repeat with currentTab in tabs of front window
      set tabTitle to ""
      set tabURL to ""
      set tabVisible to false
      try
        set tabTitle to name of currentTab
      end try
      try
        set tabURL to URL of currentTab
      end try
      try
        set tabVisible to visible of currentTab
      end try
      set end of capturedTabs to {tabTitle, tabURL, tabVisible}
    end repeat
    return capturedTabs
  end tell
  """
}

struct DemoSafariCapturer: SafariCapturing {
  func captureCurrentWindow() throws -> SafariCapture {
    DemoData.safariCapture()
  }
}
