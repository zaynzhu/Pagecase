# 页匣 · Pagecase 第一版验证结果

验证日期：2026-08-06

系统：macOS 26.5.2，Apple Silicon

工具链：Swift 6.3.3、Node.js 22.22.2、Command Line Tools

## 结论

第一版在纯演示数据下完成安全、功能、视觉、打包与性能验证。整个过程没有加载 Chrome 扩展、没有注册真实 Native Messaging Host，也没有读取或操作用户当前的 Chrome。

真实 Chrome 集成仍标记为“待用户授权验证”。

## 自动化结果

| 项目 | 结果 |
|---|---|
| `swift build` | 通过 |
| `swift test --enable-swift-testing --disable-xctest` | 测试包构建通过 |
| `swift run PagecaseCoreChecks` | 34 项通过 |
| 扩展语法检查 | 通过 |
| 扩展 Node 测试 | 8 项通过 |
| 扩展禁止 API 扫描 | 零命中 |
| 扩展外部网络调用扫描 | 零命中 |
| Bridge 快照落盘与 ping 往返 | 通过 |
| Release `.app` 构建 | 通过 |
| ad-hoc 签名严格验证 | 通过 |
| Native Host 清单隔离安装与卸载 | 通过 |
| 应用内扩展准备与 Host 配置 | 隔离目录往返通过 |
| `.app` 内置扩展文件 | 5 项齐全并签名通过 |

当前机器没有完整 Xcode，Command Line Tools 的 Swift Testing 运行器不能正常枚举测试。项目因此同时保留标准 `Tests/PagecaseCoreTests`，并用可执行的 `PagecaseCoreChecks` 在本机实际运行同一组关键行为检查，避免把“测试包编译成功”误报为“测试已执行”。

## 安全结果

运行时代码不存在以下能力：

- 关闭标签
- 移动标签
- 丢弃或挂起标签
- 创建、解除或修改标签组
- 关闭 Chrome 窗口
- 发起 `fetch`、`XMLHttpRequest`、`WebSocket` 或 `EventSource` 请求

扩展权限精确为：

```text
tabs
tabGroups
storage
nativeMessaging
```

没有 host 权限、浏览历史、书签、下载或无痕权限。

## 视觉结果

已使用实际 Release 应用检查：

- `1080 × 700` 默认窗口
- 浅色模式
- 深色模式
- 现在、快照、设置和搜索状态
- 保存快照流程与成功反馈
- 保存后磁盘内容核对反馈
- 上下键选择、Return 执行选中项和 Escape 清空
- 500 项搜索结果跨批次选择与自动滚动
- 导出完整网址隐私提醒
- 三步连接准备、扩展标识校验和 Host 状态
- 未命名标签组、折叠状态和重复网址
- 过期实时项、离线快照项、混合搜索结果和 Return 保护
- 侧栏来源状态与设置页“已连接 / 过期”汇总
- 500 页性能夹具
- 键盘与 VoiceOver 可访问名称

验收图：

- [浅色模式](../artifacts/qa-light.png)
- [深色模式](../artifacts/qa-dark.png)
- [键盘搜索选中态](../artifacts/qa-search-keyboard.png)
- [连接准备设置页](../artifacts/qa-connection-setup.png)
- [过期与离线来源](../artifacts/qa-source-status.png)

界面遵循 `minimalist-ui` 转译后的原生规则：温暖单色、系统字体、1px 分隔、低饱和分组脊线、克制圆角，无渐变、重阴影、玻璃拟态或卡片墙。

## 性能结果

Release 应用载入 500 个网页项后空闲 60 秒：

| 指标 | 实测 | 门槛 |
|---|---:|---:|
| 应用常驻内存（60 秒） | 72MB | 目标 ≤80MB，上限 ≤100MB |
| 应用物理内存足迹（60 秒） | 40MB | ≤100MB |
| 应用空闲 CPU（60 秒） | 0.4% | ≤1% |
| Bridge 常驻内存 | 约 1.7MB | ≤25MB |
| Bridge 空闲 CPU | 0.0% | ≤1% |

长分组首次只建立 40 行视图，长搜索首次建立 50 行视图；全部网页仍可搜索，其余内容按需分批展示。这个调整将 500 页首次实现中的约 150MB 内存和约 20% 轮询 CPU 降至最终结果。

本轮还在 500 项搜索结果中连续向下移动 55 次，确认选中项可以越过首批 50 项、加载下一批并自动滚动到第 56 项。

连接诊断每 2 秒检查一次 Host 清单和来源新鲜度，但只有状态实际变化时才发布界面更新。来源跨过 30 秒边界时只触发一次状态更新。修正后重新空闲 60 秒，最终结果保持在目标内。

## 未验证项

- 在真实 Chrome 中加载扩展
- 注册到真实 Chrome 配置的 Native Messaging Host
- 对真实标签执行“定位”
- 从真实快照执行“打开”
- Developer ID 正式签名、公证与自动更新

这些项目需要用户单独授权，不影响当前演示版和静态安全结论。
