import PagecaseCore
import SwiftUI

struct SidebarView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer()
        .frame(height: 58)

      browserSection(.chrome) {
        sidebarButton(.chromeLive, count: model.totalLiveTabs)
        sidebarButton(.chromeLibrary, count: model.chromeSnapshots.count)

        if !model.liveStates.isEmpty {
          sourceList
            .padding(.top, 4)
        }
      }

      Divider()
        .padding(.horizontal, 16)
        .padding(.vertical, 17)

      browserSection(.safari) {
        sidebarButton(.safariImport, count: nil)
        sidebarButton(.safariLibrary, count: model.safariCollections.count)

        Text("打开目标标签组后再读取，不常驻、不轮询")
          .font(.system(size: 9))
          .foregroundStyle(Palette.muted(colorScheme))
          .lineSpacing(2)
          .padding(.horizontal, 9)
          .padding(.top, 5)
      }

      Spacer()

      VStack(spacing: 5) {
        sidebarButton(.settings, count: nil)
      }
      .padding(.horizontal, 10)

      VStack(alignment: .leading, spacing: 6) {
        Text("网页离开内存")
        Text("不离开手边")
      }
      .font(.system(size: 11, weight: .medium, design: .serif))
      .foregroundStyle(Palette.muted(colorScheme))
      .padding(17)
    }
    .background(Palette.canvas(colorScheme))
  }

  private func browserSection<Content: View>(
    _ kind: BrowserKind,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Image(systemName: kind.symbol)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(kind.accentColor)
          .frame(width: 16)

        Text(kind.displayName.uppercased())
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .tracking(0.8)

        Spacer()
      }
      .foregroundStyle(Palette.muted(colorScheme))
      .padding(.horizontal, 17)

      VStack(spacing: 4) {
        content()
      }
      .padding(.horizontal, 10)
    }
  }

  private var sourceList: some View {
    VStack(spacing: 2) {
      ForEach(model.liveStates, id: \.source.id) { state in
        Button {
          model.selectedSourceId = state.source.id
          model.selectNavigation(.chromeLive)
        } label: {
          HStack(spacing: 9) {
            SourceDot(state: state, isDemoMode: model.isDemoMode)

            Text(state.source.label.replacingOccurrences(of: "Chrome · ", with: ""))
              .font(.system(size: 11))
              .lineLimit(1)

            Spacer()

            Text("\(state.tabCount)")
              .font(.system(size: 9, design: .monospaced))
              .foregroundStyle(Palette.muted(colorScheme))
          }
          .padding(.horizontal, 9)
          .frame(height: 27)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state.source.label)，\(sourceStatus(for: state))")
        .accessibilityValue("\(state.tabCount) 个网页")
        .background(
          model.selectedSourceId == state.source.id && model.selection == .chromeLive
            ? Palette.selection(colorScheme)
            : .clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 13)
      }
    }
  }

  private func sidebarButton(_ item: NavigationItem, count: Int?) -> some View {
    Button {
      model.selectNavigation(item)
    } label: {
      HStack(spacing: 10) {
        Rectangle()
          .fill(item.browserKind?.accentColor ?? Palette.muted(colorScheme))
          .frame(width: 2, height: 16)
          .opacity(model.selection == item ? 1 : 0)

        Image(systemName: item.symbol)
          .font(.system(size: 13, weight: .semibold))
          .frame(width: 17)

        Text(item.title)
          .font(.system(size: 13, weight: .medium))

        Spacer()

        if let count {
          Text("\(count)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.muted(colorScheme))
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 34)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(model.selection == item ? Palette.selection(colorScheme) : .clear)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func sourceStatus(for state: LiveState) -> String {
    if model.isDemoMode {
      return "演示来源"
    }
    switch model.sourceAvailability(for: state.source.id) {
    case .connected:
      return "已连接"
    case .stale:
      return "数据过期"
    case .missing:
      return "等待 Chrome"
    }
  }
}

private struct SourceDot: View {
  let state: LiveState
  let isDemoMode: Bool

  var body: some View {
    TimelineView(.periodic(from: .now, by: 5)) { context in
      Circle()
        .fill(color(at: context.date))
        .frame(width: 7, height: 7)
    }
  }

  private func color(at date: Date) -> Color {
    if isDemoMode {
      return BrowserKind.chrome.accentColor
    }
    return state.source.isFresh(at: date)
      ? Color(red: 0.29, green: 0.61, blue: 0.39)
      : Color(red: 0.74, green: 0.58, blue: 0.23)
  }
}
