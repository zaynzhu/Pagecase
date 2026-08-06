import PagecaseCore
import SwiftUI

struct SearchResultsView: View {
  private static let resultBatchSize = 50

  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var visibleResultCount = resultBatchSize

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          HStack {
            Text("“\(model.searchQuery)” 的 \(model.searchResults.count) 个结果")
              .font(.system(size: 24, weight: .semibold, design: .serif))
            Spacer()
            Text("↑↓ 选择 · Return 执行 · Esc 清空")
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(Palette.muted(colorScheme))
          }
          .padding(.bottom, 20)

          if model.searchResults.isEmpty {
            Text("没有找到匹配的网页。可以尝试标题、域名、标签组或快照名称。")
              .font(.system(size: 12))
              .foregroundStyle(Palette.muted(colorScheme))
              .padding(.vertical, 30)
          } else {
            ForEach(Array(visibleResults.enumerated()), id: \.element.id) { index, result in
              Button {
                model.selectSearchResult(result)
                model.activate(result)
              } label: {
                HStack(spacing: 14) {
                  Text(result.kind == .live ? "现在" : "快照")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                      result.kind == .live
                        ? Color(red: 0.12, green: 0.38, blue: 0.58)
                        : Color(red: 0.20, green: 0.42, blue: 0.23)
                    )
                    .frame(width: 34, alignment: .leading)

                  VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                      .font(.system(size: 13, weight: .medium))
                      .lineLimit(1)

                    Text("\(result.sourceLabel) › \(result.context)")
                      .font(.system(size: 10))
                      .foregroundStyle(Palette.muted(colorScheme))
                      .lineLimit(1)
                  }

                  Spacer()

                  Text(result.domain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.muted(colorScheme))
                    .lineLimit(1)

                  Text(result.kind == .live ? "定位" : "打开")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 55)
                .contentShape(Rectangle())
                .background(
                  model.selectedSearchResult?.id == result.id
                    ? Palette.selection(colorScheme)
                    : .clear
                )
              }
              .buttonStyle(.plain)
              .id(result.id)

              if index < visibleResults.count - 1 || hasMoreResults {
                Divider()
                  .padding(.leading, 60)
              }
            }

            if hasMoreResults {
              Button {
                visibleResultCount = min(
                  visibleResultCount + Self.resultBatchSize,
                  model.searchResults.count
                )
              } label: {
                HStack {
                  Image(systemName: "chevron.down")
                  Text("再显示 \(min(Self.resultBatchSize, model.searchResults.count - visibleResultCount)) 个结果")
                  Spacer()
                  Text("剩余 \(model.searchResults.count - visibleResultCount)")
                    .font(.system(size: 10, design: .monospaced))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted(colorScheme))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: 920, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .background(Palette.canvas(colorScheme))
      .onChange(of: model.searchQuery) { _, _ in
        visibleResultCount = Self.resultBatchSize
      }
      .onChange(of: model.selectedSearchResult?.id) { _, selectedId in
        revealSelection(selectedId, proxy: proxy)
      }
    }
  }

  private var visibleResults: ArraySlice<SearchResult> {
    model.searchResults.prefix(visibleResultCount)
  }

  private var hasMoreResults: Bool {
    visibleResultCount < model.searchResults.count
  }

  private func revealSelection(_ selectedId: String?, proxy: ScrollViewProxy) {
    guard let selectedId,
          let index = model.searchResults.firstIndex(where: { $0.id == selectedId }) else {
      return
    }
    if index >= visibleResultCount {
      visibleResultCount = min(
        ((index / Self.resultBatchSize) + 1) * Self.resultBatchSize,
        model.searchResults.count
      )
    }
    DispatchQueue.main.async {
      proxy.scrollTo(selectedId, anchor: .center)
    }
  }
}
