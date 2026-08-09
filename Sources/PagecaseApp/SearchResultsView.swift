import PagecaseCore
import SwiftUI

struct SearchResultsView: View {
  private static let resultBatchSize = 50

  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var visibleResultCount = resultBatchSize
  @State private var restoreTarget: GroupRestoreTarget?

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
          .padding(.bottom, 12)

          browserFilter
            .padding(.bottom, 14)

          if model.searchResults.isEmpty {
            Text(emptyMessage)
              .font(.system(size: 12))
              .foregroundStyle(Palette.muted(colorScheme))
              .padding(.vertical, 30)
          } else {
            ForEach(Array(visibleResults.enumerated()), id: \.element.id) { index, result in
              searchResultRow(result)
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
      .onChange(of: model.searchBrowserFilter) { _, _ in
        visibleResultCount = Self.resultBatchSize
      }
      .onChange(of: model.selectedSearchResult?.id) { _, selectedId in
        revealSelection(selectedId, proxy: proxy)
      }
    }
    .sheet(item: $restoreTarget) { target in
      GroupRestorePreviewSheet(target: target) {
        model.restore(group: target.group, sourceId: target.sourceId)
      }
    }
  }

  private var browserFilter: some View {
    HStack(spacing: 0) {
      ForEach(SearchBrowserFilter.allCases, id: \.self) { filter in
        Button {
          model.selectSearchBrowserFilter(filter)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: filter.symbol)
              .font(.system(size: 9, weight: .semibold))
            Text(filter.title)
              .font(.system(size: 11, weight: .semibold))
          }
          .foregroundStyle(filterColor(filter))
          .padding(.horizontal, 13)
          .frame(height: 34)
          .contentShape(Rectangle())
          .overlay(alignment: .bottom) {
            Rectangle()
              .fill(filterColor(filter))
              .frame(height: model.searchBrowserFilter == filter ? 2 : 0)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("只显示\(filter.title == "全部" ? "全部浏览器" : filter.title)搜索结果")
      }

      Spacer()
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Palette.border(colorScheme))
        .frame(height: 1)
    }
  }

  private func filterColor(_ filter: SearchBrowserFilter) -> Color {
    guard model.searchBrowserFilter == filter else {
      return Palette.muted(colorScheme)
    }
    return filter.browserKind?.accentColor ?? Palette.ink(colorScheme)
  }

  private var emptyMessage: String {
    switch model.searchBrowserFilter {
    case .all:
      return "没有找到匹配内容。可以尝试网页标题、域名、Chrome 标签组、快照或 Safari 合集名称。"
    case .chrome:
      return "Chrome 中没有匹配内容。可以切换到“全部”或只查看 Safari。"
    case .safari:
      return "Safari 合集中没有匹配内容。可以切换到“全部”或只查看 Chrome。"
    }
  }

  private func resultSummary(
    _ result: SearchResult,
    actionTitle: String
  ) -> some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Image(systemName: result.sourceKind.symbol)
            .font(.system(size: 8, weight: .semibold))
          Text(result.sourceKind.displayName.uppercased())
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(result.sourceKind.accentColor)

        Text(result.kind == .live ? "现在" : (result.sourceKind == .safari ? "合集" : "快照"))
          .font(.system(size: 9, weight: .semibold, design: .monospaced))
          .foregroundStyle(Palette.muted(colorScheme))
      }
      .frame(width: 58, alignment: .leading)

      VStack(alignment: .leading, spacing: 3) {
        Text(result.title)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)

        Text(resultContext(result))
          .font(.system(size: 10))
          .foregroundStyle(Palette.muted(colorScheme))
          .lineLimit(1)
      }

      Spacer()

      Text(resultMetadata(result))
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Palette.muted(colorScheme))
        .lineLimit(1)

      Text(actionTitle)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 52, alignment: .trailing)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity)
    .frame(minHeight: 55)
    .contentShape(Rectangle())
  }

  private func searchResultRow(_ result: SearchResult) -> some View {
    let actionEnabled = model.isSearchActionAvailable(result)
    let actionTitle = model.searchActionTitle(for: result)

    return HStack(spacing: 0) {
      Button {
        model.selectSearchResult(result)
        model.activate(result)
      } label: {
        resultSummary(result, actionTitle: actionTitle)
      }
      .buttonStyle(.plain)
      .disabled(!actionEnabled)
      .opacity(actionEnabled ? 1 : 0.62)
      .accessibilityLabel("\(result.title)，\(actionTitle)")

      if result.target == .group,
         result.kind == .snapshot,
         result.sourceKind == .chrome {
        snapshotRestoreAction(result)
      }
    }
    .background(
      model.selectedSearchResult?.id == result.id
        ? Palette.selection(colorScheme)
        : .clear
    )
  }

  private func snapshotRestoreAction(_ result: SearchResult) -> some View {
    let actionEnabled = model.isSourceActionAvailable(result.sourceId)
    let actionTitle = restoreActionTitle(result)

    return HStack(spacing: 0) {
      Divider()
        .frame(height: 24)

      Button {
        prepareRestore(result)
      } label: {
        Text(actionTitle)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Palette.muted(colorScheme))
          .frame(width: 88)
          .frame(minHeight: 55)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!actionEnabled)
      .opacity(actionEnabled ? 1 : 0.62)
      .accessibilityLabel("\(result.title)，\(actionTitle)")
    }
  }

  private func resultContext(_ result: SearchResult) -> String {
    let targetLabel = result.target == .group ? "标签组" : "网页"
    return "\(result.sourceLabel) › \(targetLabel) › \(result.context)"
  }

  private func resultMetadata(_ result: SearchResult) -> String {
    if result.target == .group {
      return "\(result.pageCount ?? 0) 个网页"
    }
    return result.domain ?? ""
  }

  private func restoreActionTitle(_ result: SearchResult) -> String {
    model.isSourceActionAvailable(result.sourceId) ? "恢复整组" : "Chrome 未连接"
  }

  private func prepareRestore(_ result: SearchResult) {
    model.selectSearchResult(result)
    guard let snapshotId = result.snapshotId,
          let group = model.searchGroup(for: result) else {
      model.notice = AppNotice(kind: .warning, message: "这个标签组已经不在当前快照中")
      return
    }
    restoreTarget = GroupRestoreTarget(
      snapshotId: snapshotId,
      sourceId: result.sourceId,
      sourceLabel: model.chromeSourceLabel(for: result.sourceId),
      group: group,
      preview: model.groupRestorePreview(for: group, sourceId: result.sourceId)
    )
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
