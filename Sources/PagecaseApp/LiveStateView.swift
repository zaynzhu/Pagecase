import PagecaseCore
import SwiftUI

private struct GroupSaveTarget: Identifiable {
  let sourceId: String
  let windowId: Int
  let groupId: Int
  let groupTitle: String
  let pageCount: Int

  var id: String {
    "\(sourceId)-\(windowId)-\(groupId)"
  }
}

private struct LiveGroupKey: Hashable {
  let windowId: Int
  let groupId: Int
}

private enum LiveGroupFilter: CaseIterable {
  case all
  case needsSaving
  case archived

  var title: String {
    switch self {
    case .all:
      return "全部"
    case .needsSaving:
      return "需保存"
    case .archived:
      return "已收纳"
    }
  }

  var symbol: String {
    switch self {
    case .all:
      return "rectangle.stack"
    case .needsSaving:
      return "exclamationmark.circle"
    case .archived:
      return "checkmark.circle.fill"
    }
  }
}

private struct LiveGroupReadinessSummary {
  let totalCount: Int
  let archivedCount: Int

  var needsSavingCount: Int {
    max(totalCount - archivedCount, 0)
  }

  func count(for filter: LiveGroupFilter) -> Int {
    switch filter {
    case .all:
      return totalCount
    case .needsSaving:
      return needsSavingCount
    case .archived:
      return archivedCount
    }
  }
}

struct LiveStateView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var showingSaveSheet = false
  @State private var groupSaveTarget: GroupSaveTarget?
  @State private var groupFilter = LiveGroupFilter.all

  var body: some View {
    Group {
      if let state = model.selectedLiveState {
        let groupCoverages = groupCoverages(in: state)
        let groupReadiness = groupReadinessSummary(groupCoverages)

        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
              header(state)
              groupReadinessToolbar(groupReadiness)

              let windows = filteredWindows(
                in: state,
                groupCoverages: groupCoverages
              )
              if windows.isEmpty {
                groupFilterEmptyState(groupReadiness)
              } else {
                ForEach(windows) { window in
                  WindowSection(
                    window: window,
                    action: { page in
                      model.focus(page: page, sourceId: state.source.id)
                    },
                    actionTitle: model.liveActionTitle(for: state.source.id),
                    actionEnabled: model.isSourceActionAvailable(state.source.id),
                    isGroupExpanded: { groupId in
                      model.isGroupExpanded(
                        scope: "live:\(state.source.id)",
                        windowId: window.id,
                        groupId: groupId
                      )
                    },
                    toggleGroupExpansion: { groupId in
                      model.toggleGroupExpansion(
                        scope: "live:\(state.source.id)",
                        windowId: window.id,
                        groupId: groupId
                      )
                    },
                    groupCoverage: { group in
                      groupCoverages[
                        LiveGroupKey(windowId: window.id, groupId: group.id)
                      ]
                    },
                    chromePresence: { _ in nil },
                    groupActionTitle: { group in
                      groupActionTitle(
                        for: groupCoverages[
                          LiveGroupKey(windowId: window.id, groupId: group.id)
                        ]
                      )
                    },
                    groupActionEnabled: { _ in true },
                    groupAction: { group in
                      handleGroupAction(
                        group,
                        windowId: window.id,
                        sourceId: state.source.id
                      )
                    }
                  )
                }
              }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
          }
          .background(Palette.canvas(colorScheme))
          .onAppear {
            focusRequestedGroup(state: state, using: proxy)
          }
          .onChange(of: model.groupFocusRequest) { _, _ in
            groupFilter = .all
            focusRequestedGroup(state: state, using: proxy)
          }
        }
        .sheet(isPresented: $showingSaveSheet) {
          SnapshotNameSheet(
            title: "保存当前现场",
            initialName: defaultSnapshotName(state),
            confirmTitle: "保存快照"
          ) { name in
            model.createSnapshot(name: name)
          }
        }
        .sheet(item: $groupSaveTarget) { target in
          SnapshotNameSheet(
            title: "保存「\(target.groupTitle)」",
            initialName: defaultGroupSnapshotName(target),
            confirmTitle: "保存该组"
          ) { name in
            model.createGroupSnapshot(
              sourceId: target.sourceId,
              windowId: target.windowId,
              groupId: target.groupId,
              name: name
            )
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

        snapshotCoverageStatus(state)
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

  private func snapshotCoverageStatus(_ state: LiveState) -> some View {
    let coverage = SnapshotCoverageEvaluator.evaluate(
      liveState: state,
      snapshots: model.snapshots
    )

    return Label {
      Text(snapshotCoverageMessage(coverage))
        .lineLimit(1)
    } icon: {
      Image(systemName: snapshotCoverageSymbol(coverage))
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(snapshotCoverageColor(coverage))
    .help("按完整网址、重复数量和标签组名称与颜色核对")
  }

  private func snapshotCoverageMessage(_ coverage: SnapshotCoverage) -> String {
    if coverage.livePageCount == 0 {
      return "当前没有需要保存的网页"
    }
    if coverage.isComplete, let snapshot = coverage.snapshot {
      return "当前所有 \(coverage.livePageCount) 个网页已包含在「\(snapshot.name)」"
    }
    if let snapshot = coverage.snapshot {
      return "完整现场还有 \(coverage.uncoveredPageCount) 个网页未包含在「\(snapshot.name)」"
    }
    return "尚未保存完整现场，可按下方标签组状态逐组确认"
  }

  private func snapshotCoverageSymbol(_ coverage: SnapshotCoverage) -> String {
    if coverage.livePageCount == 0 {
      return "checkmark.circle"
    }
    return coverage.isComplete ? "checkmark.shield.fill" : "exclamationmark.shield"
  }

  private func snapshotCoverageColor(_ coverage: SnapshotCoverage) -> Color {
    if coverage.livePageCount == 0 {
      return Palette.muted(colorScheme)
    }
    if coverage.isComplete {
      return colorScheme == .dark
        ? Color(red: 0.49, green: 0.75, blue: 0.52)
        : Color(red: 0.20, green: 0.49, blue: 0.25)
    }
    return colorScheme == .dark
      ? Color(red: 0.88, green: 0.70, blue: 0.34)
      : Color(red: 0.63, green: 0.43, blue: 0.08)
  }

  private func groupReadinessToolbar(_ summary: LiveGroupReadinessSummary) -> some View {
    return VStack(alignment: .leading, spacing: 12) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .bottom, spacing: 24) {
          groupReadinessCopy(summary)

          Spacer()

          groupFilterControls(summary)
        }

        VStack(alignment: .leading, spacing: 10) {
          groupReadinessCopy(summary)
          groupFilterControls(summary)
        }
      }

      Divider()
    }
  }

  private func groupReadinessCopy(_ summary: LiveGroupReadinessSummary) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(summary.totalCount == 0
        ? "当前没有 Chrome 标签组"
        : "\(summary.archivedCount) / \(summary.totalCount) 个标签组已收纳")
        .font(.system(size: 12, weight: .semibold))

      Text("已收纳表示当前内容完整保存在本地快照；关闭仍由你在 Chrome 手动完成。")
        .font(.system(size: 10))
        .foregroundStyle(Palette.muted(colorScheme))
    }
  }

  private func groupFilterControls(_ summary: LiveGroupReadinessSummary) -> some View {
    HStack(spacing: 0) {
      ForEach(LiveGroupFilter.allCases, id: \.self) { filter in
        Button {
          groupFilter = filter
        } label: {
          HStack(spacing: 6) {
            Image(systemName: filter.symbol)
              .font(.system(size: 9, weight: .semibold))
              .accessibilityHidden(true)

            Text(filter.title)
              .font(.system(size: 11, weight: .semibold))

            Text("\(summary.count(for: filter))")
              .font(.system(size: 9, design: .monospaced))
              .opacity(0.75)
          }
          .foregroundStyle(groupFilterColor(filter))
          .padding(.horizontal, 11)
          .frame(height: 34)
          .contentShape(Rectangle())
          .overlay(alignment: .bottom) {
            Rectangle()
              .fill(groupFilterColor(filter))
              .frame(height: groupFilter == filter ? 2 : 0)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("只显示\(filter.title)的 Chrome 标签组，共 \(summary.count(for: filter)) 个")
        .accessibilityAddTraits(groupFilter == filter ? .isSelected : [])
      }
    }
  }

  private func groupCoverages(
    in state: LiveState
  ) -> [LiveGroupKey: GroupSnapshotCoverage] {
    var result: [LiveGroupKey: GroupSnapshotCoverage] = [:]
    for window in state.windows {
      for group in window.groups {
        result[LiveGroupKey(windowId: window.id, groupId: group.id)] = groupCoverage(
          group,
          sourceId: state.source.id
        )
      }
    }
    return result
  }

  private func groupReadinessSummary(
    _ groupCoverages: [LiveGroupKey: GroupSnapshotCoverage]
  ) -> LiveGroupReadinessSummary {
    let archivedCount = groupCoverages.values.filter(\.isComplete).count
    return LiveGroupReadinessSummary(
      totalCount: groupCoverages.count,
      archivedCount: archivedCount
    )
  }

  private func filteredWindows(
    in state: LiveState,
    groupCoverages: [LiveGroupKey: GroupSnapshotCoverage]
  ) -> [BrowserWindow] {
    guard groupFilter != .all else {
      return state.windows
    }

    return state.windows.compactMap { window in
      let groups = window.groups.filter { group in
        let key = LiveGroupKey(windowId: window.id, groupId: group.id)
        let isArchived = groupCoverages[key]?.isComplete == true
        switch groupFilter {
        case .all:
          return true
        case .needsSaving:
          return !isArchived
        case .archived:
          return isArchived
        }
      }
      guard !groups.isEmpty else {
        return nil
      }
      return BrowserWindow(
        id: window.id,
        order: window.order,
        focused: window.focused,
        groups: groups,
        ungroupedTabs: []
      )
    }
  }

  private func groupFilterEmptyState(
    _ summary: LiveGroupReadinessSummary
  ) -> some View {
    let content: (symbol: String, title: String, message: String, color: Color)

    if summary.totalCount == 0 {
      content = (
        "rectangle.stack",
        "当前没有标签组",
        "未分组网页仍可在“全部”中查看和保存完整现场。",
        Palette.muted(colorScheme)
      )
    } else {
      switch groupFilter {
      case .all:
        content = (
          "rectangle.stack",
          "当前没有网页",
          "Chrome 中出现普通网页后，页匣会在这里显示。",
          Palette.muted(colorScheme)
        )
      case .needsSaving:
        content = (
          "checkmark.circle.fill",
          "所有标签组都已收纳",
          "确认快照可用后，你可以回到 Chrome 手动关闭不常用的标签组。",
          archivedColor
        )
      case .archived:
        content = (
          "archivebox",
          "还没有已收纳的标签组",
          "切换到“需保存”，逐组保存后再决定是否在 Chrome 中关闭。",
          needsSavingColor
        )
      }
    }

    return VStack(spacing: 10) {
      Image(systemName: content.symbol)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(content.color)
        .accessibilityHidden(true)

      Text(content.title)
        .font(.system(size: 14, weight: .semibold))

      Text(content.message)
        .font(.system(size: 11))
        .foregroundStyle(Palette.muted(colorScheme))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 62)
  }

  private func groupFilterColor(_ filter: LiveGroupFilter) -> Color {
    guard groupFilter == filter else {
      return Palette.muted(colorScheme)
    }
    switch filter {
    case .all:
      return Palette.ink(colorScheme)
    case .needsSaving:
      return needsSavingColor
    case .archived:
      return archivedColor
    }
  }

  private var needsSavingColor: Color {
    colorScheme == .dark
      ? Color(red: 0.88, green: 0.70, blue: 0.34)
      : Color(red: 0.63, green: 0.43, blue: 0.08)
  }

  private var archivedColor: Color {
    colorScheme == .dark
      ? Color(red: 0.49, green: 0.75, blue: 0.52)
      : Color(red: 0.20, green: 0.49, blue: 0.25)
  }

  private func defaultSnapshotName(_ state: LiveState) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M 月 d 日现场"
    return "\(formatter.string(from: Date())) · \(state.tabCount) 个网页"
  }

  private func defaultGroupSnapshotName(_ target: GroupSaveTarget) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M 月 d 日"
    return "\(target.groupTitle) · \(formatter.string(from: Date())) · \(target.pageCount) 个网页"
  }

  private func groupActionTitle(
    for coverage: GroupSnapshotCoverage?
  ) -> String? {
    guard let coverage else {
      return nil
    }
    if coverage.isComplete {
      return "查看快照"
    }
    return coverage.snapshot == nil ? "保存该组" : "保存最新版本"
  }

  private func handleGroupAction(
    _ group: TabGroup,
    windowId: Int,
    sourceId: String
  ) {
    let coverage = groupCoverage(group, sourceId: sourceId)
    if coverage.isComplete {
      model.showSavedGroup(coverage)
      return
    }

    groupSaveTarget = GroupSaveTarget(
      sourceId: sourceId,
      windowId: windowId,
      groupId: group.id,
      groupTitle: group.displayTitle,
      pageCount: group.tabs.count
    )
  }

  private func groupCoverage(
    _ group: TabGroup,
    sourceId: String
  ) -> GroupSnapshotCoverage {
    SnapshotCoverageEvaluator.evaluate(
      group: group,
      sourceId: sourceId,
      snapshots: model.snapshots
    )
  }

  private func focusRequestedGroup(
    state: LiveState,
    using proxy: ScrollViewProxy
  ) {
    let scope = "live:\(state.source.id)"
    DispatchQueue.main.async {
      guard let request = model.consumeGroupFocusRequest(scope: scope) else {
        return
      }
      proxy.scrollTo(request.anchorId, anchor: .center)
    }
  }
}

struct WindowSection: View {
  let window: BrowserWindow
  let action: (PageItem) -> Void
  let actionTitle: String
  let actionEnabled: Bool
  let isGroupExpanded: (Int?) -> Bool
  let toggleGroupExpansion: (Int?) -> Void
  let groupCoverage: (TabGroup) -> GroupSnapshotCoverage?
  let chromePresence: (TabGroup) -> ChromeSnapshotPresence?
  let groupActionTitle: (TabGroup) -> String?
  let groupActionEnabled: (TabGroup) -> Bool
  let groupAction: ((TabGroup) -> Void)?
  var collapsedTitle = "Chrome 中已折叠"
  var ungroupedTitle = "未分组"

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
            isExpanded: isGroupExpanded(group.id),
            toggleExpansion: {
              toggleGroupExpansion(group.id)
            },
            saveCoverage: groupCoverage(group),
            chromePresence: chromePresence(group),
            collapsedTitle: collapsedTitle,
            actionTitle: actionTitle,
            actionEnabled: actionEnabled,
            action: action,
            groupActionTitle: groupActionTitle(group),
            groupActionEnabled: groupActionEnabled(group),
            groupAction: groupAction.map { action in
              { action(group) }
            }
          )
          .id("group-\(window.id)-\(group.id)")
        }

        if !window.ungroupedTabs.isEmpty {
          PageGroupView(
            title: ungroupedTitle,
            color: ChromeGroupColor.grey.displayColor,
            pages: window.ungroupedTabs,
            collapsed: false,
            isExpanded: isGroupExpanded(nil),
            toggleExpansion: {
              toggleGroupExpansion(nil)
            },
            saveCoverage: nil,
            chromePresence: nil,
            collapsedTitle: collapsedTitle,
            actionTitle: actionTitle,
            actionEnabled: actionEnabled,
            action: action,
            groupActionTitle: nil,
            groupActionEnabled: false,
            groupAction: nil
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
  let isExpanded: Bool
  let toggleExpansion: () -> Void
  let saveCoverage: GroupSnapshotCoverage?
  let chromePresence: ChromeSnapshotPresence?
  let collapsedTitle: String
  let actionTitle: String
  let actionEnabled: Bool
  let action: (PageItem) -> Void
  let groupActionTitle: String?
  let groupActionEnabled: Bool
  let groupAction: (() -> Void)?

  @Environment(\.colorScheme) private var colorScheme
  @State private var visiblePageCount = pageBatchSize

  var body: some View {
    HStack(spacing: 0) {
      color
        .frame(width: 4)

      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Button(action: toggleExpansion) {
            HStack(spacing: 9) {
              Circle()
                .fill(color)
                .frame(width: 7, height: 7)

              Text(title)
                .font(.system(size: 13, weight: .semibold))

              Text("\(pages.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.muted(colorScheme))

              if let saveCoverage {
                groupCoverageLabel(saveCoverage)
              }

              if let chromePresence {
                ChromePresenceLabel(
                  presence: chromePresence,
                  context: .group
                )
              }

              if collapsed {
                Text(collapsedTitle)
                  .font(.system(size: 10))
                  .foregroundStyle(Palette.muted(colorScheme))
              }

              Spacer()

              Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.muted(colorScheme))
            }
            .padding(.horizontal, 14)
            .frame(height: 39)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(groupAccessibilityLabel)
          .accessibilityValue(isExpanded ? "已展开" : "已折叠")
          .accessibilityHint(isExpanded ? "折叠标签组" : "展开标签组")

          if let groupActionTitle, let groupAction {
            Divider()
              .frame(height: 18)

            Button(action: groupAction) {
              Text(groupActionTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.muted(colorScheme))
                .padding(.horizontal, 12)
                .frame(height: 39)
            }
            .buttonStyle(.plain)
            .disabled(!groupActionEnabled)
            .opacity(groupActionEnabled ? 1 : 0.62)
            .accessibilityLabel("\(title)，\(groupActionTitle)")
          }
        }

        if isExpanded {
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

  private var groupAccessibilityLabel: String {
    guard let chromePresence else {
      return "\(title)，\(pages.count) 个网页"
    }
    return "\(title)，\(pages.count) 个网页，\(ChromePresenceLabel.title(for: chromePresence, context: .group))"
  }

  private func groupCoverageLabel(_ coverage: GroupSnapshotCoverage) -> some View {
    Label {
      Text(groupCoverageMessage(coverage))
    } icon: {
      Image(systemName: coverage.isComplete ? "checkmark.circle.fill" : "exclamationmark.circle")
    }
    .font(.system(size: 10, weight: .medium))
    .foregroundStyle(groupCoverageColor(coverage))
    .help(groupCoverageHelp(coverage))
  }

  private func groupCoverageMessage(_ coverage: GroupSnapshotCoverage) -> String {
    if coverage.isComplete {
      return "已收纳"
    }
    if coverage.snapshot != nil {
      return "\(coverage.uncoveredPageCount) 个未保存"
    }
    return "未保存"
  }

  private func groupCoverageHelp(_ coverage: GroupSnapshotCoverage) -> String {
    if coverage.isComplete, let snapshot = coverage.snapshot {
      return "这个标签组已完整包含在「\(snapshot.name)」"
    }
    if let snapshot = coverage.snapshot {
      return "还有 \(coverage.uncoveredPageCount) 个网页未包含在「\(snapshot.name)」"
    }
    return "尚未在同来源快照中找到这个标签组"
  }

  private func groupCoverageColor(_ coverage: GroupSnapshotCoverage) -> Color {
    if coverage.isComplete {
      return colorScheme == .dark
        ? Color(red: 0.49, green: 0.75, blue: 0.52)
        : Color(red: 0.20, green: 0.49, blue: 0.25)
    }
    return colorScheme == .dark
      ? Color(red: 0.88, green: 0.70, blue: 0.34)
      : Color(red: 0.63, green: 0.43, blue: 0.08)
  }
}
