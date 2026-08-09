import PagecaseCore
import SwiftUI

struct GroupRestoreTarget: Identifiable {
  let snapshotId: String
  let sourceId: String
  let group: TabGroup

  var id: String {
    "\(snapshotId)-\(group.id)"
  }
}

struct PageItemRow: View {
  let page: PageItem
  let actionTitle: String
  let actionEnabled: Bool
  let action: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 5)
            .fill(Palette.canvas(colorScheme))
          Text(String(page.domain.prefix(1)).uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.muted(colorScheme))
        }
        .frame(width: 25, height: 25)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(page.displayTitle)
              .font(.system(size: 13, weight: page.active ? .semibold : .regular))
              .lineLimit(1)

            if page.pinned {
              Image(systemName: "pin.fill")
                .font(.system(size: 8))
                .foregroundStyle(Palette.muted(colorScheme))
                .accessibilityLabel("已固定")
            }
            if page.audible {
              Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted(colorScheme))
                .accessibilityLabel("正在播放声音")
            }
            if page.discarded {
              Text("已停用")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Palette.muted(colorScheme))
            }
          }

          Text(page.domain)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.muted(colorScheme))
            .lineLimit(1)
        }

        Spacer(minLength: 12)

        Text(actionTitle)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Palette.muted(colorScheme))
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 50)
      .contentShape(Rectangle())
      .background(page.active ? Palette.selection(colorScheme) : .clear)
    }
    .buttonStyle(.plain)
    .disabled(!actionEnabled)
    .opacity(actionEnabled ? 1 : 0.62)
    .accessibilityLabel("\(page.displayTitle)，\(actionTitle)")
  }
}

struct ConnectionBadge: View {
  let state: LiveState?
  let isDemoMode: Bool

  private func isFresh(at date: Date) -> Bool {
    guard let state else {
      return false
    }
    return state.source.isFresh(at: date)
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 5)) { context in
      let fresh = isFresh(at: context.date)

      HStack(spacing: 6) {
        Circle()
          .fill(dotColor(isFresh: fresh))
          .frame(width: 7, height: 7)
        Text(label(isFresh: fresh))
          .font(.system(size: 11, weight: .semibold))
      }
      .foregroundStyle(dotColor(isFresh: fresh))
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(backgroundColor(isFresh: fresh))
      .clipShape(Capsule())
      .accessibilityLabel(label(isFresh: fresh))
    }
  }

  private func label(isFresh: Bool) -> String {
    if isDemoMode {
      return "演示模式"
    }
    if state == nil {
      return "等待 Chrome"
    }
    return isFresh ? "已连接" : "数据过期"
  }

  private func dotColor(isFresh: Bool) -> Color {
    if isDemoMode {
      return Color(red: 0.12, green: 0.38, blue: 0.58)
    }
    if state == nil || !isFresh {
      return Color(red: 0.63, green: 0.43, blue: 0.08)
    }
    return Color(red: 0.20, green: 0.49, blue: 0.25)
  }

  private func backgroundColor(isFresh: Bool) -> Color {
    if isDemoMode {
      return Color(red: 0.88, green: 0.94, blue: 0.98)
    }
    if state == nil || !isFresh {
      return Color(red: 0.98, green: 0.95, blue: 0.86)
    }
    return Color(red: 0.93, green: 0.96, blue: 0.92)
  }
}

struct BrowserModeBadge: View {
  let kind: BrowserKind
  let label: String

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: kind.symbol)
        .font(.system(size: 10, weight: .semibold))
      Text(label)
        .font(.system(size: 11, weight: .semibold))
    }
    .foregroundStyle(kind.accentColor)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(kind.tint(colorScheme))
    .clipShape(Capsule())
    .accessibilityLabel("\(kind.displayName)，\(label)")
  }
}

struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(colorScheme == .dark ? .black : .white)
      .padding(.horizontal, 13)
      .frame(height: 32)
      .background(buttonColor(configuration.isPressed))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .opacity(isEnabled ? 1 : 0.38)
  }

  private func buttonColor(_ isPressed: Bool) -> Color {
    if colorScheme == .dark {
      return isPressed ? Color.white.opacity(0.82) : .white
    }
    return isPressed
      ? Color(red: 0.20, green: 0.20, blue: 0.20)
      : Color(red: 0.08, green: 0.08, blue: 0.08)
  }
}

struct EmptyStateView: View {
  let symbol: String
  let title: String
  let message: String

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 30, weight: .light))
        .foregroundStyle(Palette.muted(colorScheme))

      Text(title)
        .font(.system(size: 22, weight: .semibold, design: .serif))

      Text(message)
        .font(.system(size: 12))
        .foregroundStyle(Palette.muted(colorScheme))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 350)
        .lineSpacing(4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
    .background(Palette.canvas(colorScheme))
  }
}

struct NoticeView: View {
  let notice: AppNotice
  let dismiss: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(symbolColor)

      Text(notice.message)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(2)

      Button(action: dismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .bold))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("关闭提示")
    }
    .padding(.horizontal, 13)
    .frame(minHeight: 40)
    .background(Palette.surface(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
  }

  private var symbol: String {
    switch notice.kind {
    case .success:
      return "checkmark.circle.fill"
    case .warning:
      return "exclamationmark.circle.fill"
    case .error:
      return "xmark.circle.fill"
    }
  }

  private var symbolColor: Color {
    switch notice.kind {
    case .success:
      return Color(red: 0.20, green: 0.49, blue: 0.25)
    case .warning:
      return Color(red: 0.63, green: 0.43, blue: 0.08)
    case .error:
      return Color(red: 0.62, green: 0.18, blue: 0.18)
    }
  }
}

struct SnapshotNameSheet: View {
  let title: String
  let initialName: String
  let confirmTitle: String
  let namePlaceholder: String
  let onConfirm: (String) -> Bool

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @FocusState private var nameFocused: Bool

  init(
    title: String,
    initialName: String,
    confirmTitle: String,
    namePlaceholder: String = "快照名称",
    onConfirm: @escaping (String) -> Bool
  ) {
    self.title = title
    self.initialName = initialName
    self.confirmTitle = confirmTitle
    self.namePlaceholder = namePlaceholder
    self.onConfirm = onConfirm
    _name = State(initialValue: initialName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(title)
        .font(.system(size: 24, weight: .semibold, design: .serif))

      TextField(namePlaceholder, text: $name)
        .textFieldStyle(.roundedBorder)
        .focused($nameFocused)
        .onSubmit(confirm)

      Text("保存只复制本地索引，不会关闭、移动或修改浏览器中的标签。")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button("取消") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button(confirmTitle, action: confirm)
          .buttonStyle(PrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(26)
    .frame(width: 420)
    .onAppear {
      nameFocused = true
    }
  }

  private func confirm() {
    if onConfirm(name) {
      dismiss()
    }
  }
}
