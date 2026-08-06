# 采用原生 macOS 应用与只读 Chrome 桥接扩展

Website Lists 采用 SwiftUI/AppKit 原生应用、Native Messaging Host 和极简 Manifest V3 扩展，而不是纯扩展、AppleScript 应用或 Electron。Chrome 原生标签组只有扩展 API 能可靠读取，长期资料库与低内存界面更适合放在独立原生应用中；扩展只允许只读捕获，以及用户明确触发的“定位已有标签”和“新建一个标签”，代码中不实现关闭、移动、挂起或重组标签的能力。

## Consequences

- 用户首次使用需要手动加载扩展并注册 Native Messaging Host。
- 第一版必须同时测试 Swift 与 JavaScript 两套边界。
- 开发和模拟验收可以完全绕开真实 Chrome。
- 如果未来需要整组恢复，必须新增单独 ADR 并重新评估安全边界，不能在当前命令白名单中顺手加入。
