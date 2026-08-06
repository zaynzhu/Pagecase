import PagecaseCore
import SwiftUI

struct SnapshotLibraryView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var renameTarget: SavedSnapshot?
  @State private var deleteTarget: SavedSnapshot?

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
      "删除这个快照？",
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
      Text("只删除本地快照，不会影响 Chrome。")
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
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 22) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
              Text(snapshot.name)
                .font(.system(size: 29, weight: .semibold, design: .serif))

              Text("\(snapshot.createdAt.formatted(date: .long, time: .shortened)) · \(snapshot.groupCount) 个标签组 · \(snapshot.tabCount) 个网页")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.muted(colorScheme))
            }

            Spacer()

            Menu {
              Button("重命名") {
                renameTarget = snapshot
              }
              Divider()
              Button("删除快照", role: .destructive) {
                deleteTarget = snapshot
              }
            } label: {
              Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
          }

          ForEach(snapshot.windows) { window in
            WindowSection(
              window: window,
              sourceId: snapshot.sourceId,
              action: { page in
                model.open(page: page, sourceId: snapshot.sourceId)
              },
              actionTitle: model.isDemoMode || model.isSourceConnected(snapshot.sourceId)
                ? "打开"
                : "Chrome 未连接"
            )
          }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: 920, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else {
      EmptyStateView(symbol: "archivebox", title: "选择一个快照", message: "")
    }
  }
}
