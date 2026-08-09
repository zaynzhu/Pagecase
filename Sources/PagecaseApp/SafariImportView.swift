import PagecaseCore
import SwiftUI

struct SafariImportView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var showingNameSheet = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        header
        steps

        if let capture = model.safariCapture {
          capturePreview(capture)
        } else {
          capturePrompt
        }

        boundaryNote
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 30)
      .frame(maxWidth: 880, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(Palette.canvas(colorScheme))
    .sheet(isPresented: $showingNameSheet) {
      SnapshotNameSheet(
        title: "保存 Safari 合集",
        initialName: defaultCollectionName,
        confirmTitle: "保存合集",
        namePlaceholder: "合集名称"
      ) { name in
        model.saveSafariCollection(name: name)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        BrowserModeBadge(kind: .safari, label: "按需读取")

        Text("Safari 按需收纳")
          .font(.system(size: 30, weight: .semibold, design: .serif))

        Text("把当前打开的 Safari 标签组复制成独立合集。只有你点击时才读取，不安装插件，也不在后台轮询。")
          .font(.system(size: 12))
          .foregroundStyle(Palette.muted(colorScheme))
          .lineSpacing(4)
          .frame(maxWidth: 610, alignment: .leading)
      }

      Spacer()

      Text("0 常驻读取")
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(BrowserKind.safari.accentColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(BrowserKind.safari.tint(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
  }

  private var steps: some View {
    HStack(alignment: .top, spacing: 0) {
      step("01", title: "切换标签组", detail: "在 Safari 打开准备收纳的标签组，并让它位于最前方。")
      stepDivider
      step("02", title: "读取并核对", detail: "页匣只读取当前窗口的标题、网址和顺序。")
      stepDivider
      step("03", title: "保存后自行关闭", detail: "确认合集无误，再由你决定是否删除 Safari 原组。")
    }
    .padding(.vertical, 18)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(Palette.border(colorScheme))
        .frame(height: 1)
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Palette.border(colorScheme))
        .frame(height: 1)
    }
  }

  private func step(_ number: String, title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(number)
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(BrowserKind.safari.accentColor)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
      Text(detail)
        .font(.system(size: 10))
        .foregroundStyle(Palette.muted(colorScheme))
        .lineSpacing(3)
    }
    .padding(.horizontal, 18)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var stepDivider: some View {
    Rectangle()
      .fill(Palette.border(colorScheme))
      .frame(width: 1, height: 74)
  }

  private var capturePrompt: some View {
    HStack(spacing: 24) {
      ZStack {
        RoundedRectangle(cornerRadius: 10)
          .fill(BrowserKind.safari.tint(colorScheme))
        Image(systemName: "safari")
          .font(.system(size: 30, weight: .light))
          .foregroundStyle(BrowserKind.safari.accentColor)
      }
      .frame(width: 76, height: 76)

      VStack(alignment: .leading, spacing: 7) {
        Text("准备好后读取当前窗口")
          .font(.system(size: 19, weight: .semibold, design: .serif))
        Text("Safari 不公开原生标签组名称，保存时由你为这个合集命名。重复网址会原样保留。")
          .font(.system(size: 11))
          .foregroundStyle(Palette.muted(colorScheme))
          .lineSpacing(3)
      }

      Spacer()

      Button {
        model.captureSafariCurrentWindow()
      } label: {
        Label(model.isDemoMode ? "读取模拟窗口" : "读取当前窗口", systemImage: "arrow.down.doc")
      }
      .buttonStyle(PrimaryButtonStyle())
      .accessibilityHint("只在本次点击后读取 Safari 最前方窗口")
    }
    .padding(20)
    .background(Palette.surface(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
  }

  private func capturePreview(_ capture: SafariCapture) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text("已读取当前窗口")
            .font(.system(size: 20, weight: .semibold, design: .serif))
          Text("\(capture.pages.count) 个网页 · \(capture.capturedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Palette.muted(colorScheme))
        }

        Spacer()

        HStack(spacing: 8) {
          Button("重新读取") {
            model.captureSafariCurrentWindow()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Button {
            showingNameSheet = true
          } label: {
            Label("保存为合集", systemImage: "archivebox")
          }
          .buttonStyle(PrimaryButtonStyle())
        }
      }
      .padding(18)

      Divider()

      LazyVStack(spacing: 0) {
        ForEach(Array(capture.pages.enumerated()), id: \.offset) { offset, page in
          HStack(spacing: 12) {
            Text(String(format: "%02d", offset + 1))
              .font(.system(size: 9, design: .monospaced))
              .foregroundStyle(Palette.muted(colorScheme))
              .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
              Text(page.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pageDomain(page) : page.title)
                .font(.system(size: 12, weight: page.active ? .semibold : .regular))
                .lineLimit(1)
              Text(pageDomain(page))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.muted(colorScheme))
            }

            Spacer()

            if page.active {
              Text("当前页")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(BrowserKind.safari.accentColor)
            }
          }
          .padding(.horizontal, 18)
          .frame(minHeight: 48)

          if offset < capture.pages.count - 1 {
            Divider()
              .padding(.leading, 52)
          }
        }
      }

      if capture.skippedPageCount > 0 {
        Divider()
        Text("已忽略 \(capture.skippedPageCount) 个起始页、设置页或其他非 http/https 标签。")
          .font(.system(size: 10))
          .foregroundStyle(Palette.muted(colorScheme))
          .padding(16)
      }
    }
    .background(Palette.surface(colorScheme))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Palette.border(colorScheme), lineWidth: 1)
    }
  }

  private var boundaryNote: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "lock")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(BrowserKind.safari.accentColor)
      Text("按需读取不会监测 Safari 后续变化，也不会关闭、移动或修改任何现有标签。合集保存后与 Safari 原标签组彼此独立。")
        .font(.system(size: 10))
        .foregroundStyle(Palette.muted(colorScheme))
        .lineSpacing(3)
    }
  }

  private var defaultCollectionName: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M 月 d 日"
    return "Safari · \(formatter.string(from: Date()))"
  }

  private func pageDomain(_ page: SafariCapturedPage) -> String {
    guard let host = URL(string: page.url)?.host else {
      return page.url
    }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}
