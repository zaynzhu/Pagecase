import PagecaseCore
import SwiftUI

struct LibraryImportPreviewView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Group {
      if let pending = model.pendingLibraryImport {
        previewContent(pending)
      }
    }
    .background(Palette.canvas(colorScheme))
  }

  private func previewContent(_ pending: PendingLibraryImport) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 7) {
        Text("导入本地资料")
          .font(.system(size: 28, weight: .semibold, design: .serif))
        Text("先核对浏览器来源，再决定哪些资料写入页匣。")
          .font(.system(size: 12))
          .foregroundStyle(Palette.muted(colorScheme))
      }
      .padding(.bottom, 22)

      fileSummary(pending)
        .padding(.bottom, 18)

      VStack(spacing: 10) {
        ForEach(pending.preview.browserSummaries, id: \.browserKind) { summary in
          browserRow(summary, pending: pending)
        }
      }

      if pending.preview.idConflictCount > 0 {
        conflictNotice(pending.preview.idConflictCount)
          .padding(.top, 14)
      }

      HStack(spacing: 7) {
        Image(systemName: "lock")
          .font(.system(size: 10, weight: .semibold))
        Text("文件只在本机读取；取消或关闭此窗口不会写入任何资料。")
      }
      .font(.system(size: 10))
      .foregroundStyle(Palette.muted(colorScheme))
      .padding(.top, 18)

      Divider()
        .padding(.vertical, 18)

      HStack(spacing: 10) {
        Text(selectionSummary(pending))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(
            pending.selectedBrowserKinds.isEmpty
              ? Palette.muted(colorScheme)
              : Palette.ink(colorScheme)
          )

        Spacer()

        Button("取消") {
          model.cancelLibraryImport()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut(.cancelAction)

        Button("导入选中资料") {
          model.confirmLibraryImport()
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(pending.selectedBrowserKinds.isEmpty)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(28)
    .frame(width: 600)
  }

  private func fileSummary(_ pending: PendingLibraryImport) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "doc.badge.magnifyingglass")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Palette.muted(colorScheme))
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 5) {
        Text(pending.fileName)
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .lineLimit(1)
        Text(
          "由页匣 \(pending.preview.applicationVersion) 导出 · \(pending.preview.exportedAt.formatted(date: .numeric, time: .shortened))"
        )
        .font(.system(size: 10))
        .foregroundStyle(Palette.muted(colorScheme))
      }

      Spacer()

      Text("\(pending.preview.snapshotCount) 份资料")
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(Palette.muted(colorScheme))
    }
    .padding(14)
    .background(Palette.surface(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
  }

  private func browserRow(
    _ summary: LibraryImportBrowserSummary,
    pending: PendingLibraryImport
  ) -> some View {
    let isSelected = pending.selectedBrowserKinds.contains(summary.browserKind)
    return Button {
      model.togglePendingImportBrowser(summary.browserKind)
    } label: {
      HStack(alignment: .center, spacing: 13) {
        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(
            isSelected ? summary.browserKind.accentColor : Palette.muted(colorScheme)
          )
          .frame(width: 20)

        Image(systemName: summary.browserKind.symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(summary.browserKind.accentColor)
          .frame(width: 24)

        VStack(alignment: .leading, spacing: 4) {
          Text(summary.browserKind == .chrome ? "Chrome 快照" : "Safari 合集")
            .font(.system(size: 13, weight: .semibold))
          Text(browserDetail(summary))
            .font(.system(size: 10))
            .foregroundStyle(Palette.muted(colorScheme))
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 4) {
          Text("\(summary.snapshotCount) 份")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
          if summary.idConflictCount > 0 {
            Text("\(summary.idConflictCount) 份已存在")
              .font(.system(size: 9, weight: .medium))
              .foregroundStyle(warningColor)
          }
        }
      }
      .padding(.horizontal, 15)
      .frame(height: 70)
      .contentShape(Rectangle())
      .background(isSelected ? summary.browserKind.tint(colorScheme) : Palette.surface(colorScheme))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(
            isSelected
              ? summary.browserKind.accentColor.opacity(colorScheme == .dark ? 0.55 : 0.35)
              : Palette.border(colorScheme),
            lineWidth: 1
          )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(isSelected ? "取消选择" : "选择")\(summary.browserKind.displayName)，\(summary.snapshotCount) 份资料"
    )
  }

  private func browserDetail(_ summary: LibraryImportBrowserSummary) -> String {
    if summary.browserKind == .safari {
      return "\(summary.tabCount) 个网页 · 按需保存的本地合集"
    }
    return "\(summary.tabCount) 个网页 · \(summary.groupCount) 个标签组"
  }

  private func conflictNotice(_ count: Int) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: "square.on.square")
        .font(.system(size: 11, weight: .semibold))
      Text("检测到 \(count) 份资料已经存在。选中后会另存为新副本，不会覆盖或删除本地资料。")
        .lineSpacing(2)
    }
    .font(.system(size: 10))
    .foregroundStyle(warningColor)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      colorScheme == .dark
        ? Color(red: 0.20, green: 0.17, blue: 0.10)
        : Color(red: 0.98, green: 0.95, blue: 0.86)
    )
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  private func selectionSummary(_ pending: PendingLibraryImport) -> String {
    guard pending.selectedSnapshotCount > 0 else {
      return "请至少选择一个浏览器来源"
    }
    let conflictText = pending.selectedIdConflictCount > 0
      ? " · \(pending.selectedIdConflictCount) 份另存副本"
      : ""
    return "将导入 \(pending.selectedSnapshotCount) 份资料\(conflictText)"
  }

  private var warningColor: Color {
    colorScheme == .dark
      ? Color(red: 0.82, green: 0.67, blue: 0.34)
      : Color(red: 0.54, green: 0.38, blue: 0.10)
  }
}
