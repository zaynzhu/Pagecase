import PagecaseCore
import SwiftUI

struct ChromeRestoreReceiptView: View {
  let receipt: GroupRestoreReceipt
  let isDemoMode: Bool
  let dismiss: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        BrowserModeBadge(
          kind: .chrome,
          label: isDemoMode ? "回执演示" : "恢复回执"
        )

        Text(receipt.sourceLabel)
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(Palette.muted(colorScheme))
          .lineLimit(1)

        Spacer()

        Button(action: dismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 9, weight: .bold))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.muted(colorScheme))
        .accessibilityLabel("关闭 Chrome 恢复回执")
      }

      HStack(alignment: .top, spacing: 11) {
        Image(systemName: statusSymbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(statusColor)
          .frame(width: 22, height: 22)

        VStack(alignment: .leading, spacing: 4) {
          Text(receipt.title)
            .font(.system(size: 18, weight: .semibold, design: .serif))
          Text(receipt.summary)
            .font(.system(size: 11))
            .foregroundStyle(Palette.muted(colorScheme))
            .lineSpacing(2)
        }
      }
      .padding(.top, 15)

      metrics
        .padding(.top, 15)

      if receipt.status != .success && receipt.status != .timeout {
        Text(receipt.message)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(statusColor)
          .padding(.top, 11)
      }

      HStack(alignment: .top, spacing: 8) {
        Image(systemName: guidanceSymbol)
          .font(.system(size: 10, weight: .semibold))
          .frame(width: 13)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          if isDemoMode {
            Text("演示结果，没有操作真实 Chrome。")
              .fontWeight(.semibold)
          }
          Text(receipt.guidance)
        }
        .font(.system(size: 10))
        .lineSpacing(2)
      }
      .foregroundStyle(statusColor)
      .padding(.horizontal, 11)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(statusBackground)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .padding(.top, 13)
    }
    .padding(16)
    .frame(width: 380)
    .background(Palette.surface(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 9))
    .overlay {
      RoundedRectangle(cornerRadius: 9)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private var metrics: some View {
    HStack(spacing: 0) {
      metric(label: "已创建", value: createdValue)
      Divider()
        .frame(height: 32)
      metric(label: "应创建", value: "\(receipt.expectedTabCount)")
      Divider()
        .frame(height: 32)
      metric(label: "标签组", value: groupValue)
    }
    .padding(.vertical, 10)
    .background(Palette.canvas(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
  }

  private func metric(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(Palette.muted(colorScheme))
      Text(value)
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 11)
  }

  private var createdValue: String {
    receipt.createdTabCount.map(String.init) ?? "待确认"
  }

  private var groupValue: String {
    switch receipt.groupCreated {
    case let .some(isCreated):
      return isCreated ? "已成组" : "未成组"
    case .none:
      return "待确认"
    }
  }

  private var statusSymbol: String {
    switch receipt.status {
    case .success:
      return "checkmark.circle.fill"
    case .partial:
      return "exclamationmark.triangle.fill"
    case .failure:
      return "xmark.circle.fill"
    case .timeout:
      return "clock.badge.exclamationmark"
    }
  }

  private var guidanceSymbol: String {
    receipt.status == .success ? "lock" : "arrow.trianglehead.2.clockwise.rotate.90"
  }

  private var statusColor: Color {
    switch receipt.status {
    case .success:
      return colorScheme == .dark
        ? Color(red: 0.49, green: 0.72, blue: 0.48)
        : Color(red: 0.20, green: 0.49, blue: 0.25)
    case .partial, .timeout:
      return colorScheme == .dark
        ? Color(red: 0.82, green: 0.67, blue: 0.34)
        : Color(red: 0.54, green: 0.38, blue: 0.10)
    case .failure:
      return colorScheme == .dark
        ? Color(red: 0.84, green: 0.48, blue: 0.46)
        : Color(red: 0.62, green: 0.18, blue: 0.18)
    }
  }

  private var statusBackground: Color {
    switch receipt.status {
    case .success:
      return colorScheme == .dark
        ? Color(red: 0.12, green: 0.19, blue: 0.12)
        : Color(red: 0.93, green: 0.96, blue: 0.92)
    case .partial, .timeout:
      return colorScheme == .dark
        ? Color(red: 0.20, green: 0.17, blue: 0.10)
        : Color(red: 0.98, green: 0.95, blue: 0.86)
    case .failure:
      return colorScheme == .dark
        ? Color(red: 0.22, green: 0.12, blue: 0.12)
        : Color(red: 0.99, green: 0.92, blue: 0.92)
    }
  }
}
