import PagecaseCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  @State private var showingRemoveConnectionConfirmation = false

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

          browserLibraryRow(
            kind: .chrome,
            count: model.chromeSnapshots.count,
            detail: "完整现场与标签组快照"
          ) {
            model.exportLibrary(browserKind: .chrome)
          }

          Divider()

          browserLibraryRow(
            kind: .safari,
            count: model.safariCollections.count,
            detail: "按需读取后保存的本地合集"
          ) {
            model.exportLibrary(browserKind: .safari)
          }

          Divider()

          HStack(spacing: 10) {
            Button("导入本地资料") {
              model.importLibrary()
            }
            Button("导出全部资料") {
              model.exportLibrary()
            }
            .disabled(model.snapshots.isEmpty)
            Spacer()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)

          Text("导出文件包含网页完整网址和可能存在的查询参数。")
            .font(.system(size: 10))
            .foregroundStyle(Palette.muted(colorScheme))

          Text("导入会先显示 Chrome 与 Safari 分区预览，确认前不会写入本地资料。")
            .font(.system(size: 10))
            .foregroundStyle(Palette.muted(colorScheme))
        }

        settingsSection("连接 Chrome") {
          connectionStep(
            number: "1",
            title: "加载只读连接器",
            detail: "准备并显示扩展文件夹。在 Chrome 地址栏打开 chrome://extensions，启用开发者模式，再选择“加载已解压的扩展程序”。"
          ) {
            Button("显示扩展文件") {
              model.revealExtensionDirectory()
            }
            .disabled(!model.extensionPackageAvailable)
          }

          Divider()

          connectionStep(
            number: "2",
            title: "粘贴扩展标识",
            detail: "加载后，复制 Chrome 显示的 32 位扩展标识。页匣只允许这个扩展与本机 Bridge 通信。"
          ) {
            VStack(alignment: .leading, spacing: 7) {
              TextField("32 位扩展标识", text: $model.extensionId)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(Palette.canvas(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                  RoundedRectangle(cornerRadius: 5)
                    .stroke(Palette.border(colorScheme), lineWidth: 1)
                }

              if !model.extensionId.isEmpty, !model.canConfigureNativeHost {
                Text("扩展标识应为 32 位，只包含 a–p。")
                  .font(.system(size: 10))
                  .foregroundStyle(Color(red: 0.63, green: 0.43, blue: 0.08))
              }
            }
          }

          Divider()

          connectionStep(
            number: "3",
            title: "配置本地连接",
            detail: model.isDemoMode
              ? "演示模式只写入隔离目录，不会注册到真实 Chrome。"
              : "这一步只写入 Chrome 的 Native Messaging Host 清单，不会读取或改变任何标签。"
          ) {
            HStack(spacing: 10) {
              Button("配置本地连接") {
                model.configureNativeHost()
              }
              .buttonStyle(PrimaryButtonStyle())
              .disabled(!model.canConfigureNativeHost)

              if model.nativeHostStatus.state != .missing {
                Button("移除连接") {
                  showingRemoveConnectionConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
              }
            }
          }

          Divider()

          nativeHostStatus
        }

        settingsSection("连接状态") {
          settingRow(
            symbol: "app.connected.to.app.below.fill",
            title: "Chrome 来源",
            detail: sourceSummary
          )

          Divider()

          settingRow(
            symbol: "point.3.connected.trianglepath.dotted",
            title: "Native Messaging Bridge",
            detail: model.isDemoMode
              ? "演示数据，不连接 Chrome"
              : (model.hasConnectedSource ? "已连接" : model.nativeHostStatus.detail)
          )
        }

        settingsSection("Safari 按需收纳") {
          settingRow(
            symbol: "safari",
            title: "接入方式",
            detail: "只在点击时读取当前窗口，不安装插件、不后台轮询"
          )

          Divider()

          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.badge.checkmark")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(BrowserKind.safari.accentColor)
              .frame(width: 18)

            VStack(alignment: .leading, spacing: 6) {
              Text("Safari 合集与 Chrome 快照分开显示")
                .font(.system(size: 12, weight: .medium))
              Text("第一次真实读取时，macOS 会询问是否允许页匣访问 Safari。页匣不读取正文，也不会修改标签。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted(colorScheme))
                .lineSpacing(3)
            }

            Spacer()

            Button("打开按需收纳") {
              model.selectNavigation(.safariImport)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }

        settingsSection("安全边界") {
          VStack(alignment: .leading, spacing: 12) {
            safetyLine("不会自动关闭标签", symbol: "xmark.bin")
            safetyLine("不会移动、挂起或重新分组标签", symbol: "rectangle.3.group")
            safetyLine("Safari 只在点击时读取当前窗口", symbol: "safari")
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
    .confirmationDialog(
      "移除本地连接配置？",
      isPresented: $showingRemoveConnectionConfirmation,
      titleVisibility: .visible
    ) {
      Button("移除连接", role: .destructive) {
        model.removeNativeHost()
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("只删除页匣的 Host 清单，不删除扩展、本地资料或 Chrome 标签。")
    }
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

  private func browserLibraryRow(
    kind: BrowserKind,
    count: Int,
    detail: String,
    export: @escaping () -> Void
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: kind.symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(kind.accentColor)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 3) {
        Text(kind == .chrome ? "Chrome 快照" : "Safari 合集")
          .font(.system(size: 12, weight: .medium))
        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(Palette.muted(colorScheme))
      }

      Spacer()

      Text("\(count) 份")
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Palette.muted(colorScheme))

      Button("单独导出", action: export)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(count == 0)
    }
  }

  private func safetyLine(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 12))
      .foregroundStyle(Palette.ink(colorScheme))
  }

  private var sourceSummary: String {
    if model.isDemoMode {
      return "\(model.liveStates.count) 个演示来源，\(model.totalLiveTabs) 个网页"
    }
    if model.liveStates.isEmpty {
      return "尚未连接"
    }
    return "\(model.connectedSourceCount) 个已连接，\(model.staleSourceCount) 个过期，\(model.totalLiveTabs) 个网页"
  }

  private func connectionStep<Content: View>(
    number: String,
    title: String,
    detail: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(number)
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .frame(width: 24, height: 24)
        .background(Palette.canvas(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
          RoundedRectangle(cornerRadius: 5)
            .stroke(Palette.border(colorScheme), lineWidth: 1)
        }

      VStack(alignment: .leading, spacing: 7) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))

        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(Palette.muted(colorScheme))
          .lineSpacing(3)

        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var nativeHostStatus: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: nativeHostStatusSymbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(nativeHostStatusColor)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 3) {
        Text(model.nativeHostStatus.detail)
          .font(.system(size: 11, weight: .medium))

        if let extensionId = model.nativeHostStatus.extensionId {
          Text(extensionId)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Palette.muted(colorScheme))
            .textSelection(.enabled)
        }
      }
    }
  }

  private var nativeHostStatusSymbol: String {
    switch model.nativeHostStatus.state {
    case .missing:
      return "circle.dashed"
    case .ready:
      return "checkmark.circle.fill"
    case .invalid:
      return "exclamationmark.triangle.fill"
    }
  }

  private var nativeHostStatusColor: Color {
    switch model.nativeHostStatus.state {
    case .missing:
      return Palette.muted(colorScheme)
    case .ready:
      return Color(red: 0.20, green: 0.49, blue: 0.25)
    case .invalid:
      return Color(red: 0.63, green: 0.43, blue: 0.08)
    }
  }
}
