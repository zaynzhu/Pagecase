import PagecaseCore
import SwiftUI

struct SidebarView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer()
        .frame(height: 58)

      VStack(spacing: 5) {
        sidebarButton(.live, count: model.totalLiveTabs)
        sidebarButton(.snapshots, count: model.snapshots.count)
        sidebarButton(.settings, count: nil)
      }
      .padding(.horizontal, 10)

      if !model.liveStates.isEmpty {
        Text("来源")
          .font(.system(size: 10, weight: .semibold))
          .textCase(.uppercase)
          .tracking(0.8)
          .foregroundStyle(Palette.muted(colorScheme))
          .padding(.horizontal, 17)
          .padding(.top, 28)
          .padding(.bottom, 9)

        VStack(spacing: 2) {
          ForEach(model.liveStates, id: \.source.id) { state in
            Button {
              model.selectedSourceId = state.source.id
              model.selection = .live
              model.searchQuery = ""
            } label: {
              HStack(spacing: 9) {
                SourceDot(state: state, isDemoMode: model.isDemoMode)

                Text(state.source.label)
                  .font(.system(size: 12))
                  .lineLimit(1)

                Spacer()

                Text("\(state.tabCount)")
                  .font(.system(size: 10, design: .monospaced))
                  .foregroundStyle(Palette.muted(colorScheme))
              }
              .padding(.horizontal, 8)
              .frame(height: 30)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
              "\(state.source.label)，\(sourceStatus(for: state))"
            )
            .accessibilityValue("\(state.tabCount) 个网页")
            .background(
              model.selectedSourceId == state.source.id && model.selection == .live
                ? Palette.selection(colorScheme)
                : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
          }
        }
        .padding(.horizontal, 10)
      }

      Spacer()

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

  private func sidebarButton(_ item: NavigationItem, count: Int?) -> some View {
    Button {
      model.selection = item
      model.searchQuery = ""
    } label: {
      HStack(spacing: 10) {
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
      return Color(red: 0.33, green: 0.56, blue: 0.72)
    }
    return state.source.isFresh(at: date)
      ? Color(red: 0.29, green: 0.61, blue: 0.39)
      : Color(red: 0.74, green: 0.58, blue: 0.23)
  }
}
