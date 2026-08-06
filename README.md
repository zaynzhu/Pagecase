# 页匣 · Pagecase

> 网页离开内存，不离开手边。

页匣是一款面向低内存 Mac 的本地网页资料库。它通过一个极小的 Chrome 扩展只读保存现有窗口、标签组、网页顺序和重复网址，再由原生 macOS 应用负责搜索、快照与单页找回。

![页匣浅色界面](artifacts/qa-light.png)

## 第一版能做什么

- 只读展示 Chrome 普通窗口、原生标签组和网页项
- 主动保存不可变快照
- 搜索标题、域名、网址、标签组和快照名称，支持上下键选择、Return 执行和 Escape 清空
- 点击实时网页时定位已有标签
- 点击快照网页时只新建一个标签
- 过期与离线来源继续可见，但定位和打开操作会明确禁用
- 保存后从磁盘重新核对，导入采用事务替换，不留下半份资料
- 导入与导出完整本地资料库，导出前提示完整网址隐私风险
- `.app` 自带 Chrome 连接器，可在设置中准备扩展文件、诊断并配置本地 Host
- 支持浅色、深色、键盘导航和 VoiceOver

页匣不会自动关闭、移动、挂起、解除分组或重新分组任何 Chrome 标签，也不读取网页正文、截图、历史记录或无痕窗口。

## 结构

```text
PagecaseApp       SwiftUI/AppKit 原生应用
PagecaseBridge    Chrome Native Messaging Host
extension/        Manifest V3 只读连接器
PagecaseCore      JSON 数据、快照、搜索与命令模型
```

应用和 Bridge 不使用 Electron、WebView、数据库、云端服务或第三方运行时。

## 构建应用

要求 macOS 14 或更高版本、Swift 6 和 Command Line Tools。

```bash
./scripts/build-app.sh
```

构建产物位于：

```text
dist/页匣.app
```

## 安全演示

下面的方式只使用隔离演示数据，不连接 Chrome：

```bash
PAGECASE_DEMO=1 \
PAGECASE_DATA_ROOT="$(mktemp -d)/pagecase" \
"dist/页匣.app/Contents/MacOS/PagecaseApp" --demo
```

视觉验收可以额外设置：

```bash
PAGECASE_APPEARANCE=light
PAGECASE_APPEARANCE=dark
PAGECASE_PERFORMANCE=1
```

## 验证

```bash
swift build
swift test --enable-swift-testing --disable-xctest
swift run PagecaseCoreChecks
npm run check:extension
npm run test:extension
npm run test:bridge
./scripts/validate-extension.sh
```

当前第一版已经通过：

- 34 项 Swift 核心行为检查
- 8 项 Chrome 扩展测试
- Bridge 快照落盘与协议往返检查
- 禁止 API 与网络调用静态扫描
- Release 构建、ad-hoc 签名和安装清单隔离测试
- 浅色与深色真实窗口验收
- 500 项搜索结果跨批次键盘导航验收
- 隔离目录中的扩展准备、Host 配置、状态核对与精确移除
- 过期来源在实时列表、快照、搜索、侧栏和设置中的一致性验收
- 500 页空闲 60 秒性能验收

详细结果见 [第一版验证结果](docs/VALIDATION-RESULTS.md)。

## Chrome 集成状态

真实扩展加载与 Native Messaging Host 注册尚未执行。开发和当前验收没有读取、关闭、移动或改动用户现有的 Chrome 页面。

实际使用时不需要终端：

1. 打开页匣的“设置”。
2. 点击“显示扩展文件”。
3. 在 Chrome 地址栏打开 `chrome://extensions`，启用开发者模式。
4. 选择“加载已解压的扩展程序”，使用页匣准备的文件夹。
5. 将 Chrome 显示的扩展标识粘贴回页匣，点击“配置本地连接”。

页匣不会替用户打开 Chrome 页面，也不会自动安装或修改扩展。命令行脚本继续作为备用方式：

```bash
./scripts/install-native-host.sh <Chrome 扩展标识>
```

卸载脚本只删除精确的 Host 清单，不删除应用数据：

```bash
./scripts/uninstall-native-host.sh
```

## 本地数据

正式模式默认保存在：

```text
~/Library/Application Support/Pagecase/
```

完整网址可能包含敏感查询参数。导出的 JSON 文件应按浏览数据妥善保管。

## 设计与边界

- [产品设计](docs/PRODUCT.md)
- [视觉与交互](docs/VISUAL-DESIGN.md)
- [技术架构](docs/ARCHITECTURE.md)
- [验证计划](docs/VALIDATION.md)
