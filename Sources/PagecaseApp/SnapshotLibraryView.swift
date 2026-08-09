import PagecaseCore
import SwiftUI

private struct GroupRestoreTarget: Identifiable {
  let snapshotId: String
  let sourceId: String
  let group: TabGroup

  var id: String {
    "\(snapshotId)-\(group.id)"
  }
}

struct SnapshotLibraryView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var renameTarget: SavedSnapshot?
  @State private var deleteTarget: SavedSnapshot?
  @State private var restoreTarget: GroupRestoreTarget?

  var body: some View {
    Group {
      if model.snapshots.isEmpty {
        EmptyStateView(
          symbol: "archivebox",
          title: "还没有快照",
          message: "在“现在”页面保存当前现场。快照会保留窗口、标签组、顺序和重复网址。"
        )
      } else {
        HSplitView {
          index
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)

          detail
            .frame(minWidth: 520)
        }
        .background(Palette.canvas(colorScheme))
      }
    }
    .sheet(item: $renameTarget) { snapshot in
      SnapshotNameSheet(
        title: "重命名快照",
        initialName: snapshot.name,
        confirmTitle: "保存名称"
      ) { name in
        model.renameSnapshot(snapshot, name: name)
      }
    }
    .confirmationDialog(
      deleteDialogTitle,
      isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("删除快照", role: .destructive) {
        if let deleteTarget {
          model.deleteSnapshot(deleteTarget)
        }
        deleteTarget = nil
      }
      Button("取消", role: .cancel) {
        deleteTarget = nil
      }
    } message: {
      Text(deleteDialogMessage)
    }
    .confirmationDialog(
      restoreDialogTitle,
      isPresented: Binding(
        get: { restoreTarget != nil },
        set: { if !$0 { restoreTarget = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let restoreTarget {
        Button("打开 \(restoreTarget.group.tabs.count) 个网页") {
          model.restore(
            group: restoreTarget.group,
            sourceId: restoreTarget.sourceId
          )
          self.restoreTarget = nil
        }
      }
      Button("取消", role: .cancel) {
        restoreTarget = nil
      }
    } message: {
      Text("将在 Chrome 中按原顺序新建并组合这些网页，不会关闭、移动或改变任何已有标签。")
    }
  }

  private var index: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("快照")
        .font(.system(size: 24, weight: .semibold, design: .serif))
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 16)

      Divider()

      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(model.snapshots) { snapshot in
            Button {
              model.selectedSnapshotId = snapshot.id
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.name)
                  .font(.system(size: 13, weight: .semibold, design: .serif))
                  .lineLimit(2)
                  .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                  Text(snapshotScopeTitle(snapshot))
                  Text(snapshot.createdAt.formatted(date: .abbreviated, time: .omitted))
                  Spacer()
                  Text("\(snapshot.tabCount) 页")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.muted(colorScheme))
              }
              .padding(10)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
              model.selectedSnapshotId == snapshot.id
                ? Palette.selection(colorScheme)
                : .clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
          }
        }
        .padding(8)
      }
    }
    .background(Palette.surface(colorScheme))
  }

  @ViewBuilder
  private var detail: some View {
    if let snapshot = model.selectedSnapshot {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 7) {
                Text(snapshot.name)
                  .font(.system(size: 29, weight: .semibold, design: .serif))

                Text("\(snapshotScopeDetailTitle(snapshot)) · \(snapshot.createdAt.formatted(date: .long, time: .shortened)) · \(snapshot.groupCount) 个标签组 · \(snapshot.tabCount) 个网页")
                  .font(.system(size: 11, design: .monospaced))
                  .foregroundStyle(Palette.muted(colorScheme))
              }

              Spacer()

              HStack(spacing: 8) {
                Menu {
                  Button("重命名") {
                    renameTarget = snapshot
                  }
                } label: {
                  Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("更多快照操作")

                Button(role: .destructive) {
                  deleteTarget = snapshot
                } label: {
                  Label("删除快照", systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("从本机删除这份快照")
                .accessibilityHint("删除前会再次确认，不会影响 Chrome")
              }
            }

            ForEach(snapshot.windows) { window in
              WindowSection(
                window: window,
                action: { page in
                  model.open(page: page, sourceId: snapshot.sourceId)
                },
                actionTitle: model.snapshotActionTitle(for: snapshot.sourceId),
                actionEnabled: model.isSourceActionAvailable(snapshot.sourceId),
                isGroupExpanded: { groupId in
                  model.isGroupExpanded(
                    scope: "snapshot:\(snapshot.id)",
                    windowId: window.id,
                    groupId: groupId
                  )
                },
                toggleGroupExpansion: { groupId in
                  model.toggleGroupExpansion(
                    scope: "snapshot:\(snapshot.id)",
                    windowId: window.id,
                    groupId: groupId
                  )
                },
                groupCoverage: { _ in nil },
                groupActionTitle: { _ in
                  model.snapshotGroupActionTitle(for: snapshot.sourceId)
                },
                groupActionEnabled: { _ in
                  model.isSourceActionAvailable(snapshot.sourceId)
                },
                groupAction: { group in
                  restoreTarget = GroupRestoreTarget(
                    snapshotId: snapshot.id,
                    sourceId: snapshot.sourceId,
                    group: group
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
        .onAppear {
          focusRequestedGroup(using: proxy)
        }
        .onChange(of: model.snapshotGroupFocusRequest) { _, _ in
          focusRequestedGroup(using: proxy)
        }
      }
    } else {
      EmptyStateView(symbol: "archivebox", title: "选择一个快照", message: "")
    }
  }

  private var restoreDialogTitle: String {
    guard let restoreTarget else {
      return "恢复标签组？"
    }
    return "恢复「\(restoreTarget.group.displayTitle)」？"
  }

  private var deleteDialogTitle: String {
    guard let deleteTarget else {
      return "删除这个快照？"
    }
    return "删除「\(deleteTarget.name)」？"
  }

  private var deleteDialogMessage: String {
    guard let deleteTarget else {
      return "只删除本地快照，不会影响 Chrome。"
    }
    return "将从本机永久删除这份包含 \(deleteTarget.tabCount) 个网页的快照。此操作无法撤销，但不会影响 Chrome。"
  }

  private func snapshotScopeTitle(_ snapshot: SavedSnapshot) -> String {
    snapshot.scope == .group ? "标签组" : "完整现场"
  }

  private func snapshotScopeDetailTitle(_ snapshot: SavedSnapshot) -> String {
    snapshot.scope == .group ? "标签组快照" : "完整现场快照"
  }

  private func focusRequestedGroup(using proxy: ScrollViewProxy) {
    guard let request = model.consumeSnapshotGroupFocusRequest(),
          request.snapshotId == model.selectedSnapshot?.id else {
      return
    }
    DispatchQueue.main.async {
      proxy.scrollTo(request.anchorId, anchor: .center)
    }
  }
}
