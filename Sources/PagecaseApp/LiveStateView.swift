import PagecaseCore
import SwiftUI

struct LiveStateView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var showingSaveSheet = false

  var body: some View {
    Group {
      if let state = model.selectedLiveState {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 22) {
            header(state)

            ForEach(state.windows) { window in
              WindowSection(
                window: window,
                sourceId: state.source.id,
                action: { page in
                  model.focus(page: page, sourceId: state.source.id)
                },
                actionTitle: model.liveActionTitle(for: state.source.id),
                actionEnabled: model.isSourceActionAvailable(state.source.id)
              )
            }
          }
          .padding(.horizontal, 28)
          .padding(.vertical, 26)
          .frame(maxWidth: 920, alignment: .leading)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Palette.canvas(colorScheme))
        .sheet(isPresented: $showingSaveSheet) {
          SnapshotNameSheet(
            title: "保存当前现场",
            initialName: defaultSnapshotName(state),
            confirmTitle: "保存快照"
          ) { name in
            model.createSnapshot(name: name)
          }
        }
      } else {
        EmptyStateView(
          symbol: "rectangle.stack.badge.questionmark",
          title: "等待 Chrome",
          message: "连接扩展后，这里会只读显示现有窗口与标签组。开发演示不会连接真实 Chrome。"
        )
      }
    }
  }

  private func header(_ state: LiveState) -> some View {
    HStack(alignment: .top, spacing: 18) {
      VStack(alignment: .leading, spacing: 7) {
        Text("现在")
          .font(.system(size: 30, weight: .semibold, design: .serif))

        Text("\(state.source.label) · \(state.windows.count) 个窗口 · \(state.groupCount) 个标签组 · \(state.tabCount) 个网页 · 最后更新 \(state.source.capturedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(Palette.muted(colorScheme))
      }

      Spacer()

      Button {
        showingSaveSheet = true
      } label: {
        Label("保存当前现场", systemImage: "archivebox")
      }
      .buttonStyle(PrimaryButtonStyle())
      .accessibilityHint("复制当前现场到本地快照，不会改变 Chrome")
    }
  }

  private func defaultSnapshotName(_ state: LiveState) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M 月 d 日现场"
    return "\(formatter.string(from: Date())) · \(state.tabCount) 个网页"
  }
}

struct WindowSection: View {
  let window: BrowserWindow
  let sourceId: String
  let action: (PageItem) -> Void
  let actionTitle: String
  let actionEnabled: Bool

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("窗口 \(window.order + 1)")
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .foregroundStyle(Palette.muted(colorScheme))

        if window.focused {
          Text("当前窗口")
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(red: 0.88, green: 0.94, blue: 0.98))
            .foregroundStyle(Color(red: 0.12, green: 0.38, blue: 0.58))
            .clipShape(Capsule())
        }

        Spacer()

        Text("\(window.tabCount) 个网页")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(Palette.muted(colorScheme))
      }

      VStack(spacing: 12) {
        ForEach(window.groups) { group in
          PageGroupView(
            title: group.displayTitle,
            color: group.color.displayColor,
            pages: group.tabs,
            collapsed: group.collapsed,
            actionTitle: actionTitle,
            actionEnabled: actionEnabled,
            action: action
          )
        }

        if !window.ungroupedTabs.isEmpty {
          PageGroupView(
            title: "未分组",
            color: ChromeGroupColor.grey.displayColor,
            pages: window.ungroupedTabs,
            collapsed: false,
            actionTitle: actionTitle,
            actionEnabled: actionEnabled,
            action: action
          )
        }
      }
    }
  }
}

struct PageGroupView: View {
  private static let pageBatchSize = 40

  let title: String
  let color: Color
  let pages: [PageItem]
  let collapsed: Bool
  let actionTitle: String
  let actionEnabled: Bool
  let action: (PageItem) -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var visiblePageCount = pageBatchSize

  var body: some View {
    HStack(spacing: 0) {
      color
        .frame(width: 4)

      VStack(spacing: 0) {
        HStack(spacing: 9) {
          Circle()
            .fill(color)
            .frame(width: 7, height: 7)

          Text(title)
            .font(.system(size: 13, weight: .semibold))

          Text("\(pages.count)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.muted(colorScheme))

          if collapsed {
            Text("Chrome 中已折叠")
              .font(.system(size: 10))
              .foregroundStyle(Palette.muted(colorScheme))
          }

          Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 39)

        Divider()

        ForEach(visiblePages) { page in
          PageItemRow(
            page: page,
            actionTitle: actionTitle,
            actionEnabled: actionEnabled
          ) {
            action(page)
          }

          if page.id != visiblePages.last?.id || hasMorePages {
            Divider()
              .padding(.leading, 48)
          }
        }

        if hasMorePages {
          Button {
            visiblePageCount = min(
              visiblePageCount + Self.pageBatchSize,
              pages.count
            )
          } label: {
            HStack {
              Image(systemName: "chevron.down")
              Text("再显示 \(min(Self.pageBatchSize, pages.count - visiblePageCount)) 个网页")
              Spacer()
              Text("剩余 \(pages.count - visiblePageCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.muted(colorScheme))
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 15)
            .frame(height: 40)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .background(Palette.surface(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
  }

  private var visiblePages: ArraySlice<PageItem> {
    pages.prefix(visiblePageCount)
  }

  private var hasMorePages: Bool {
    visiblePageCount < pages.count
  }
}
