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

struct LiveStateView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var showingSaveSheet = false
  @State private var groupSaveTarget: GroupSaveTarget?

  var body: some View {
    Group {
      if let state = model.selectedLiveState {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
              header(state)

              ForEach(state.windows) { window in
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
                    SnapshotCoverageEvaluator.evaluate(
                      group: group,
                      sourceId: state.source.id,
                      snapshots: model.snapshots
                    )
                  },
                  groupActionTitle: { group in
                    groupActionTitle(for: group, sourceId: state.source.id)
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

  private func groupActionTitle(for group: TabGroup, sourceId: String) -> String {
    let coverage = SnapshotCoverageEvaluator.evaluate(
      group: group,
      sourceId: sourceId,
      snapshots: model.snapshots
    )
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
    let coverage = SnapshotCoverageEvaluator.evaluate(
      group: group,
      sourceId: sourceId,
      snapshots: model.snapshots
    )
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

  private func focusRequestedGroup(
    state: LiveState,
    using proxy: ScrollViewProxy
  ) {
    let scope = "live:\(state.source.id)"
    guard let request = model.consumeGroupFocusRequest(scope: scope) else {
      return
    }
    DispatchQueue.main.async {
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
  let groupActionTitle: (TabGroup) -> String?
  let groupActionEnabled: (TabGroup) -> Bool
  let groupAction: ((TabGroup) -> Void)?
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

              if collapsed {
                Text("Chrome 中已折叠")
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
          .accessibilityLabel("\(title)，\(pages.count) 个网页")
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
      return "已保存"
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
