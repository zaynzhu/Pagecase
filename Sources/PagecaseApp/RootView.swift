import PagecaseCore
import SwiftUI

struct RootView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.scenePhase) private var scenePhase
  @FocusState private var searchFocused: Bool

  private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        SidebarView(model: model)
          .frame(width: 208)

        Divider()

        VStack(spacing: 0) {
          topBar

          Divider()

          Group {
            if isSearchActive {
              SearchResultsView(model: model)
            } else {
              selectedContent
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }

      Divider()

      footer
    }
    .background(Palette.canvas(colorScheme))
    .foregroundStyle(Palette.ink(colorScheme))
    .onReceive(refreshTimer) { _ in
      model.refresh()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        model.refresh()
      }
    }
    .onAppear {
      focusSearchIfRequested()
    }
    .onChange(of: model.searchFocusRequest) { _, _ in
      focusSearchIfRequested()
    }
    .onChange(of: model.searchQuery) { _, _ in
      model.handleSearchQueryChange()
    }
    .overlay(alignment: .topTrailing) {
      VStack(alignment: .trailing, spacing: 10) {
        if let receipt = model.chromeRestoreReceipt, shouldShowChromeReceipt {
          ChromeRestoreReceiptView(
            receipt: receipt,
            isDemoMode: model.isDemoMode
          ) {
            model.dismissChromeRestoreReceipt()
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }

        if let notice = model.notice {
          NoticeView(notice: notice) {
            model.dismissNotice()
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .padding(.top, 54)
      .padding(.trailing, 18)
    }
    .animation(.easeOut(duration: 0.18), value: model.notice)
    .animation(.easeOut(duration: 0.18), value: model.chromeRestoreReceipt)
    .sheet(item: $model.pendingLibraryImport) { _ in
      LibraryImportPreviewView(model: model)
    }
  }

  private func focusSearchIfRequested() {
    if model.consumeSearchFocusRequest() {
      searchFocused = true
    }
  }

  private var topBar: some View {
    HStack(spacing: 18) {
      VStack(alignment: .leading, spacing: 1) {
        Text("页匣")
          .font(.system(size: 20, weight: .semibold, design: .serif))
        Text("PAGECASE")
          .font(.system(size: 9, weight: .semibold, design: .monospaced))
          .tracking(1.3)
          .foregroundStyle(Palette.muted(colorScheme))
      }
      .frame(width: 102, alignment: .leading)

      HStack(spacing: 9) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Palette.muted(colorScheme))

        TextField("搜索 Chrome 快照或 Safari 合集", text: $model.searchQuery)
          .textFieldStyle(.plain)
          .font(.system(size: 13))
          .focused($searchFocused)
          .onSubmit {
            model.activateSelectedSearchResult()
          }

        if model.searchQuery.isEmpty {
          Text("⌘K")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.muted(colorScheme))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Palette.canvas(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
              RoundedRectangle(cornerRadius: 4)
                .stroke(Palette.border(colorScheme), lineWidth: 1)
            }
        } else {
          Button {
            model.clearSearch()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(Palette.muted(colorScheme))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清空搜索")
        }
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: 540, minHeight: 34)
      .background(Palette.surface(colorScheme))
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .overlay {
        RoundedRectangle(cornerRadius: 7)
          .stroke(Palette.border(colorScheme), lineWidth: 1)
      }

      Spacer(minLength: 8)

      contextBadge
    }
    .padding(.leading, 22)
    .padding(.trailing, 18)
    .frame(height: 58)
    .background(Palette.canvas(colorScheme))
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch model.selection {
    case .chromeLive:
      LiveStateView(model: model)
    case .chromeLibrary, .safariLibrary:
      SnapshotLibraryView(model: model)
    case .safariImport:
      SafariImportView(model: model)
    case .settings:
      SettingsView(model: model)
    }
  }

  @ViewBuilder
  private var contextBadge: some View {
    if isSearchActive {
      searchContextBadge
    } else if model.selection.browserKind == .safari {
      BrowserModeBadge(
        kind: .safari,
        label: model.isDemoMode ? "Safari 演示" : "仅在点击时读取"
      )
    } else {
      ConnectionBadge(
        state: model.selectedLiveState,
        isDemoMode: model.isDemoMode
      )
    }
  }

  @ViewBuilder
  private var searchContextBadge: some View {
    if let browserKind = model.searchBrowserFilter.browserKind {
      BrowserModeBadge(kind: browserKind, label: "仅看 \(browserKind.displayName)")
    } else {
      HStack(spacing: 6) {
        HStack(spacing: 3) {
          Image(systemName: BrowserKind.chrome.symbol)
            .foregroundStyle(BrowserKind.chrome.accentColor)
          Image(systemName: BrowserKind.safari.symbol)
            .foregroundStyle(BrowserKind.safari.accentColor)
        }
        .font(.system(size: 9, weight: .semibold))

        Text("全部浏览器")
          .font(.system(size: 11, weight: .semibold))
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(Palette.selection(colorScheme))
      .clipShape(Capsule())
      .accessibilityLabel("搜索全部浏览器")
    }
  }

  private var isSearchActive: Bool {
    !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var shouldShowChromeReceipt: Bool {
    if model.selection.browserKind == .safari {
      return false
    }
    return !isSearchActive || model.searchBrowserFilter != .safari
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock")
        .font(.system(size: 10, weight: .semibold))
      Text("数据只保存在本机")
      Text("·")
      Text("不会自动关闭、移动或重组 Chrome 与 Safari 标签")
      Spacer()
      if model.isDemoMode {
        Text(model.isPerformanceMode ? "500 页性能演示" : "演示数据")
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
      }
    }
    .font(.system(size: 11))
    .foregroundStyle(Palette.muted(colorScheme))
    .padding(.horizontal, 16)
    .frame(height: 30)
    .background(Palette.canvas(colorScheme))
  }
}
