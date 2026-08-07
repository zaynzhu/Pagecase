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
            if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
      model.resetSearchSelection()
    }
    .overlay(alignment: .topTrailing) {
      if let notice = model.notice {
        NoticeView(notice: notice) {
          model.dismissNotice()
        }
        .padding(.top, 54)
        .padding(.trailing, 18)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.18), value: model.notice)
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

        TextField("搜索网页、标签组或快照", text: $model.searchQuery)
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

      ConnectionBadge(
        state: model.selectedLiveState,
        isDemoMode: model.isDemoMode
      )
    }
    .padding(.leading, 22)
    .padding(.trailing, 18)
    .frame(height: 58)
    .background(Palette.canvas(colorScheme))
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch model.selection {
    case .live:
      LiveStateView(model: model)
    case .snapshots:
      SnapshotLibraryView(model: model)
    case .settings:
      SettingsView(model: model)
    }
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock")
        .font(.system(size: 10, weight: .semibold))
      Text("数据只保存在本机")
      Text("·")
      Text("不会自动关闭、移动或重组已有 Chrome 标签")
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
