import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        VStack(alignment: .leading, spacing: 7) {
          Text("设置")
            .font(.system(size: 30, weight: .semibold, design: .serif))
          Text("只保留连接、数据和安全相关的必要信息。")
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted(colorScheme))
        }

        settingsSection("本地资料") {
          settingRow(
            symbol: "folder",
            title: "数据目录",
            detail: model.paths.root.path(percentEncoded: false)
          )

          Divider()

          HStack(spacing: 10) {
            Button("导入资料库") {
              model.importLibrary()
            }
            Button("导出资料库") {
              model.exportLibrary()
            }
            Spacer()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        settingsSection("连接状态") {
          settingRow(
            symbol: "app.connected.to.app.below.fill",
            title: "Chrome 来源",
            detail: model.liveStates.isEmpty
              ? "尚未连接"
              : "\(model.liveStates.count) 个来源，\(model.totalLiveTabs) 个网页"
          )

          Divider()

          settingRow(
            symbol: "point.3.connected.trianglepath.dotted",
            title: "Native Messaging Bridge",
            detail: model.isDemoMode
              ? "演示模式未启用"
              : (model.hasConnectedSource ? "已连接" : "等待扩展连接")
          )
        }

        settingsSection("安全边界") {
          VStack(alignment: .leading, spacing: 12) {
            safetyLine("不会自动关闭标签", symbol: "xmark.bin")
            safetyLine("不会移动、挂起或重新分组标签", symbol: "rectangle.3.group")
            safetyLine("不读取网页正文、截图或浏览历史", symbol: "doc.text.magnifyingglass")
            safetyLine("不登录、不联网、不上传数据", symbol: "lock")
          }
        }

        Text("Pagecase \(AppModel.applicationVersion)")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(Palette.muted(colorScheme))
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 26)
      .frame(maxWidth: 760, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(Palette.canvas(colorScheme))
  }

  private func settingsSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Palette.muted(colorScheme))

      VStack(spacing: 12) {
        content()
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.surface(colorScheme))
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(Palette.border(colorScheme), lineWidth: 1)
      }
    }
  }

  private func settingRow(symbol: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Palette.muted(colorScheme))
        .frame(width: 18)

      Text(title)
        .font(.system(size: 12, weight: .medium))
        .frame(width: 150, alignment: .leading)

      Text(detail)
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Palette.muted(colorScheme))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func safetyLine(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 12))
      .foregroundStyle(Palette.ink(colorScheme))
  }
}
