import PagecaseCore
import SwiftUI

struct GroupRestorePreviewSheet: View {
  let target: GroupRestoreTarget
  let onConfirm: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        BrowserModeBadge(kind: .chrome, label: "恢复预览")

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.muted(colorScheme))
        .accessibilityLabel("关闭恢复预览")
      }

      Text(target.group.displayTitle)
        .font(.system(size: 28, weight: .semibold, design: .serif))
        .padding(.top, 17)

      Text("恢复到 \(target.sourceLabel)，并按快照中的顺序、组名和颜色重新建立标签组。")
        .font(.system(size: 12))
        .foregroundStyle(Palette.muted(colorScheme))
        .lineSpacing(3)
        .padding(.top, 7)

      metrics
        .padding(.top, 22)

      if target.preview.alreadyOpenPageCount > 0 {
        duplicateNotice
          .padding(.top, 14)
      } else {
        noDuplicateNotice
          .padding(.top, 14)
      }

      safetyNotice
        .padding(.top, 10)

      Divider()
        .padding(.vertical, 18)

      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Chrome 会一次创建 \(target.preview.pageCount) 个标签")
            .font(.system(size: 11, weight: .medium))
          Text("恢复期间内存占用可能短时上升。")
            .font(.system(size: 10))
            .foregroundStyle(Palette.muted(colorScheme))
        }

        Spacer()

        Button("取消") {
          dismiss()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut(.cancelAction)

        Button("恢复 \(target.preview.pageCount) 个网页") {
          onConfirm()
          dismiss()
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(28)
    .frame(width: 560)
    .background(Palette.canvas(colorScheme))
  }

  private var metrics: some View {
    HStack(spacing: 0) {
      metric(label: "组内网页", value: target.preview.pageCount)

      Divider()
        .frame(height: 42)

      metric(label: "当前已打开", value: target.preview.alreadyOpenPageCount)

      Divider()
        .frame(height: 42)

      metric(label: "将新建", value: target.preview.pageCount)
    }
    .padding(.vertical, 13)
    .background(Palette.surface(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "组内 \(target.preview.pageCount) 个网页，当前已打开 \(target.preview.alreadyOpenPageCount) 个，将新建 \(target.preview.pageCount) 个"
    )
  }

  private func metric(label: String, value: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Palette.muted(colorScheme))
      Text("\(value)")
        .font(.system(size: 19, weight: .semibold, design: .monospaced))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
  }

  private var duplicateNotice: some View {
    notice(
      symbol: "square.on.square",
      text: "其中 \(target.preview.alreadyOpenPageCount) 个网页的网址已在这个 Chrome 来源中打开。为保留原标签组语境，页匣仍会全部新建，不自动去重。",
      foreground: warningColor,
      background: warningBackground
    )
  }

  private var noDuplicateNotice: some View {
    notice(
      symbol: "checkmark.circle",
      text: "按当前 Chrome 现场，没有发现与这个标签组相同的网址。",
      foreground: successColor,
      background: successBackground
    )
  }

  private var safetyNotice: some View {
    notice(
      symbol: "lock",
      text: "只组合本次恢复新建的标签；不会关闭、移动、挂起或重新分组任何已有标签。",
      foreground: BrowserKind.chrome.accentColor,
      background: BrowserKind.chrome.tint(colorScheme)
    )
  }

  private func notice(
    symbol: String,
    text: String,
    foreground: Color,
    background: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 14)
      Text(text)
        .font(.system(size: 10))
        .lineSpacing(3)
    }
    .foregroundStyle(foreground)
    .padding(.horizontal, 13)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(background)
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  private var warningColor: Color {
    colorScheme == .dark
      ? Color(red: 0.82, green: 0.67, blue: 0.34)
      : Color(red: 0.54, green: 0.38, blue: 0.10)
  }

  private var warningBackground: Color {
    colorScheme == .dark
      ? Color(red: 0.20, green: 0.17, blue: 0.10)
      : Color(red: 0.98, green: 0.95, blue: 0.86)
  }

  private var successColor: Color {
    colorScheme == .dark
      ? Color(red: 0.49, green: 0.72, blue: 0.48)
      : Color(red: 0.20, green: 0.49, blue: 0.25)
  }

  private var successBackground: Color {
    colorScheme == .dark
      ? Color(red: 0.12, green: 0.19, blue: 0.12)
      : Color(red: 0.93, green: 0.96, blue: 0.92)
  }
}
