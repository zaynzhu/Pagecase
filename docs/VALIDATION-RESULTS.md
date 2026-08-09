# 页匣 · Pagecase 0.6 验证结果

验证日期：2026-08-09

系统：macOS 26.5.2，Apple Silicon

工具链：Swift 6.3.3、Node.js 22.22.2、Command Line Tools

## 结论

0.6 完成 Safari 按需收纳、Safari 合集、持久化浏览器来源，以及 Chrome／Safari 明确分区。导入增加只读分区预览和来源选择，确认前不写入；Chrome 实时页增加“全部 / 需保存 / 已收纳”状态筛选。Chrome 整组恢复进一步增加来源、重复网址、新建数量和内存影响预览，并在执行后用结构化回执区分完整成功、部分完成、失败与超时。Safari 只在用户点击时读取最前方窗口；没有插件、后台轮询或常驻辅助进程，两种浏览器的资料库、打开流程与结果反馈保持独立。

自动化、视觉和性能验收全部使用独立应用标识、临时数据目录与模拟浏览器数据。没有加载扩展、注册真实 Native Messaging Host、触发 Apple Events 权限，也没有读取或操作用户当前的 Chrome、Safari 和现有 `dist/页匣.app`。

## 自动化结果

| 项目 | 结果 |
|---|---|
| `swift build` | 通过 |
| `swift test --enable-swift-testing --disable-xctest` | 测试包构建通过 |
| `swift run PagecaseCoreChecks` | 98 项通过 |
| Chrome 扩展语法检查 | 通过 |
| Chrome 扩展 Node 测试 | 13 项通过 |
| Chrome 危险 API、分组恢复与网络扫描 | 通过，禁止项零命中 |
| Safari 按需读取静态安全检查 | 通过 |
| Safari AppleScript 只编译检查 | `osacompile` 通过，未执行脚本 |
| Bridge 快照、结构化结果与 ping 往返 | 通过 |
| Release Swift 构建 | 通过 |
| 隔离 Release `.app` ad-hoc 签名 | 严格验证通过 |
| 应用版本与构建号 | `0.6.0` / `7` |
| `NSAppleEventsUsageDescription` | 已包含并核对 |
| `.app` 内置 Chrome 扩展文件 | 5 项齐全 |
| 隔离 Release 应用体积 | 5.1MB |

当前机器没有完整 Xcode。Command Line Tools 的 Swift Testing 运行器不能正常枚举测试，因此 `swift test` 用于编译标准测试包，`PagecaseCoreChecks` 在本机实际执行同一组关键行为检查。页匣的构建、运行和 Safari 按需收纳均不依赖完整 Xcode。

## 数据与行为结果

新增检查覆盖：

- Safari 合集持久保存 `sourceKind = safari`、来源名称和 `scope = collection`。
- 合集恰好包含一个窗口、零个标签组和至少一个 Web 页面。
- 页面顺序、重复网址和当前页保持不变，非 `http/https` 项不会进入合集。
- 空名称、空捕获和伪装成 Chrome 的合集会被拒绝。
- 旧版 JSON 缺少浏览器来源字段时继续按 Chrome 解码。
- Chrome 与 Safari 不互相参与快照覆盖判断。
- Safari 合集不会进入 Chrome 标签组版本序列。
- Chrome 标签组收纳状态继续复用严格覆盖判断；保存一个标签组后从磁盘核对，计数从“0 / 3”更新为“1 / 3”，需保存集合从 3 组减少为 2 组。
- Chrome 恢复预览只匹配同一 `sourceId` 的 Chrome 实时来源；相同网址按重复次数计数，Safari 或另一 Chrome 来源不会混入。
- 恢复预览只报告当前相同网址，不删减或改写快照网页列表；最终恢复数量始终等于原标签组网页数。
- 扩展结果准确返回动作、已创建数量、是否成组以及 `validation`、`creatingTabs`、`groupingTabs`、`updatingGroup` 失败阶段。
- 恢复回执先核对命令标识、Chrome 来源与动作；完整创建且成组为成功，已经创建标签或成组后更新失败为部分完成，零副作用错误为失败，30 秒无结果为超时。
- 旧版缺少结构化字段的成功结果继续可读；来源或动作错配的结果不会被当成本次恢复成功。
- 部分完成和超时都不会触发自动清理或重试，已经创建的标签保持在 Chrome 中供用户核对。
- 仓库保存后重新从磁盘读取，来源与内容核对一致。
- 全局搜索同时返回 Chrome 与 Safari 内容，并保留明确浏览器来源。
- Chrome 与 Safari 专属搜索在数据集合层完全排除另一浏览器，全部范围仍同时保留两类结果。
- Chrome 专属导出包含 4 份 Chrome 快照且零 Safari；Safari 专属导出包含 1 份 Safari 合集且零 Chrome。
- 混合资料库导入预览准确显示 4 份 Chrome 快照、1 份 Safari 合集及 5 份本地标识冲突，预览前后资料完全一致。
- 空来源选择零写入；Safari 专属导入只新增 1 份 Safari 合集，随后 Chrome 专属导入只新增 4 份 Chrome 快照。
- 删除一个浏览器的记录不会把选择回落到另一浏览器资料库。

演示夹具现在包含 2 个 Chrome 来源、33 个 Chrome 网页、4 个 Chrome 快照和 1 个 Safari 合集。Safari 模拟捕获包含 4 个可保存网页、1 个跳过项和 1 个重复网址；视觉保存后隔离资料库显示 2 个 Safari 合集，Chrome 快照仍保持 4 个。

## 安全结果

Chrome 扩展继续不存在关闭、移动、挂起、解除分组或关闭窗口 API，也没有外部网络调用。`restoreGroup` 仍只把本次命令创建的 `createdTabIds` 交给分组 API。

Safari 静态检查确认：

- 读取器没有 `Timer`、`DispatchSourceTimer`、应用启动通知或分离后台任务。
- AppleScript 只遍历 `tabs of front window`，读取标签名称、网址和当前页状态。
- 脚本没有 `close`、`quit`、`delete`、`move`、`activate`、`make new`、`open location`、`do JavaScript` 或修改标签属性的语句。
- 演示模式注入 `DemoSafariCapturer`，不会执行真实 AppleScript。
- 捕获结果只保存在内存预览中，用户命名确认后才经统一模型校验与原子 JSON 写入。

Safari 单页打开和“打开全部”也只由用户点击触发；演示模式会阻止这些动作进入真实 Safari。

## 视觉结果

通过 Computer Use 对独立的 `com.zaynzhu.pagecase.qa06final`、`com.zaynzhu.pagecase.qasearch`、`com.zaynzhu.pagecase.qaimport` 与 `com.zaynzhu.pagecase.qareadiness` 演示应用完成浅色与深色验收：

- 侧栏固定分成 `CHROME` 与 `SAFARI`，分别使用浏览器图标、名称、识别色和独立数量。
- Chrome 只显示“现在 / 快照 / 实时来源”；Safari 只显示“按需收纳 / 合集”。
- Chrome 快照资料库不会出现 Safari 合集，Safari 合集资料库不会出现 Chrome 快照。
- Safari 首屏清楚表达“0 常驻读取”和三步流程。
- 模拟读取后显示 4 个网页、顺序、当前页、重复网址及 1 个跳过项。
- 保存弹窗使用“合集名称”和浏览器中性安全说明，不再出现 Chrome 标签文案。
- 默认名称缩短为“Safari · 日期”，保存后不会在索引和标题中异常换行。
- Safari 合集详情使用独立来源徽章、“合集网页”和“在 Safari 打开全部”，不出现 Chrome 恢复语义。
- 全局搜索混排时每行同时显示浏览器图标、浏览器名称和“现在 / 快照 / 合集”。
- 搜索结果顶部使用平直的“全部 / Chrome / Safari”来源切换；Chrome 范围 32 项全部为 Chrome，Safari 范围 2 项全部为 Safari。
- 顶栏徽章同步显示“全部浏览器”“仅看 Chrome”或“仅看 Safari”，不再沿用进入搜索前的页面来源。
- 清空搜索后再次搜索会恢复全部浏览器范围，来源筛选空状态提供明确切换建议。
- 设置页分别显示 4 份 Chrome 快照、1 份 Safari 合集及各自“单独导出”，完整导入导出保持为次级动作。
- 导入预览以蓝色 Chrome 行和紫色 Safari 行明确分区，显示文件来源、网页、标签组和冲突数量；两行都取消时确认按钮禁用。
- 隔离交互中只选择 Safari 后，Safari 合集从 1 份变为 2 份，Chrome 快照保持 4 份；再次打开后取消，数量保持不变。
- Chrome 实时页显示“已收纳 / 标签组总数”以及带数量的“全部 / 需保存 / 已收纳”平直筛选，选中态同时进入可访问性树。
- 隔离夹具先移除一个完整现场快照，再从界面保存其中一组：计数从 0 / 3 变为 1 / 3，“需保存”只保留另外 2 组，“已收纳”只显示刚保存的 1 组。
- “需保存”为空时明确提示所有组均已收纳，仍说明关闭由用户在 Chrome 手动完成；从搜索定位被隐藏组时自动恢复“全部”并滚动到目标。
- 未分组网页仅在“全部”显示；过滤后的窗口网页数按当前可见组重新计算，不会把隐藏网页误报为筛选结果。
- 收纳筛选没有出现在 Safari 按需收纳或合集页面；浅色、深色和约 900px 窄窗口都没有截断、重叠或来源混淆。
- 深色模式保持足够对比度，没有渐变、重阴影、玻璃拟态或大面积高饱和色。
- Chrome 快照与搜索中的“恢复整组”共用同一专属预览：目标来源、三列数量、重复网址说明、安全边界和短时内存提示完整可见。
- 浅色模式完整成功回执显示 3／3 个标签与“已成组”；深色模式部分完成回执同时显示已创建标签、未成组、失败原因以及“不自动清理或重试”。
- Chrome 回执进入 Safari 合集后完全隐藏，页面中只保留 Safari 徽章和动作；返回 Chrome 快照后同一回执重新出现，没有发生跨浏览器状态转换。
- Safari 合集仍使用独立的“在 Safari 打开 N 个网页”系统确认，没有出现 Chrome 恢复徽章、重复网址计数或标签组语义。

本轮新增验收图：

- [Chrome 与 Safari 分区](../artifacts/qa-browser-separation.png)
- [Safari 按需收纳](../artifacts/qa-safari-import.png)
- [Safari 合集资料库](../artifacts/qa-safari-library.png)
- [跨浏览器搜索来源](../artifacts/qa-mixed-search.png)
- [Safari 按需收纳深色模式](../artifacts/qa-safari-import-dark.png)
- [全部浏览器搜索范围](../artifacts/qa-search-browser-filter.png)
- [Safari 专属搜索范围](../artifacts/qa-search-safari-filter.png)
- [搜索来源筛选深色模式](../artifacts/qa-search-browser-filter-dark.png)
- [浏览器分区备份设置](../artifacts/qa-settings-browser-backups.png)
- [浏览器分区导入预览](../artifacts/qa-import-preview.png)
- [浏览器分区导入预览深色模式](../artifacts/qa-import-preview-dark.png)
- [Chrome 标签组收纳筛选](../artifacts/qa-group-readiness.png)
- [Chrome 标签组收纳筛选深色模式](../artifacts/qa-group-readiness-dark.png)
- [Chrome 标签组恢复预览](../artifacts/qa-group-restore-preview.png)
- [Chrome 标签组恢复预览深色模式](../artifacts/qa-group-restore-preview-dark.png)
- [Chrome 标签组恢复成功回执](../artifacts/qa-restore-receipt-success.png)
- [Chrome 标签组部分完成回执深色模式](../artifacts/qa-restore-receipt-partial-dark.png)
- [Safari 页面隐藏 Chrome 回执](../artifacts/qa-restore-receipt-safari-hidden.png)

界面延续 `minimalist-ui` 的原生转译：温暖单色、清晰排版、1px 分隔、克制圆角和低饱和来源色。Safari 没有另起一套视觉系统，而是在同一资料柜语言中形成明确但安静的来源边界。

## 性能结果

隔离 Release 应用载入 500 个 Chrome 网页，空闲 60 秒后测量：

| 指标 | 实测 | 门槛 |
|---|---:|---:|
| 应用物理内存足迹 | 46MB | 目标 ≤80MB，上限 ≤100MB |
| 应用 RSS（诊断值） | 60 秒后约 98.1MB | 记录共享框架与图形映射，不单独作为内存压力结论 |
| 应用 CPU（10 次稳定采样平均） | 约 0.44%，最终 0.1% | ≤1% |
| 菜单栏驻留物理内存足迹 | 47MB | ≤100MB |
| 菜单栏驻留 RSS（诊断值） | 107.9MB | 记录 |
| 菜单栏驻留 CPU | 0.0% | ≤1% |
| Bridge RSS | 7.6MB | ≤25MB |
| Bridge 空闲 CPU | 0.0% | ≤1% |

500 页长分组首次只建立 40 行视图，其余按需加载。收纳状态筛选只对内存中的 Chrome 标签组和已有快照求值；搜索筛选只是结果集合的来源条件，分区导出和导入预览都只在用户点击后执行，没有增加轮询器、数据库、WebView 或额外进程。

本轮同机 500 页 Release 进程在空闲 60 秒后物理内存足迹为 46MB，RSS 约 98.1MB；10 次稳定 CPU 采样平均约 0.44%，最终采样为 0.1%，均低于验收上限。恢复预览和回执只在用户点击及对应命令结果到达时建立，没有增加轮询器、数据库、WebView 或额外常驻进程。

## 打包结果

- `swift build -c release` 在 Command Line Tools 环境通过。
- 使用 Release 二进制组装的隔离 `.app` 可启动，ad-hoc 签名通过 `codesign --verify --deep --strict`。
- `Info.plist` 已核对 macOS 14、版本 `0.6.0`、构建号 `7` 和 Safari 自动化用途说明。
- Chrome 连接器的 5 个运行与说明文件全部进入应用包，当前隔离应用包为 5.1MB。
- 本轮没有运行会替换 `dist/页匣.app` 的正式打包脚本，避免影响用户当前安装；正式产物可在用户决定升级时再生成。

## 未验证项

- 真实 Safari 首次自动化权限提示与授权路径。
- 从真实 Safari 最前方窗口读取标题、网址、顺序和当前页。
- 从真实 Safari 合集打开单页或打开全部。
- 自动化加载真实 Chrome 扩展或注册 Native Messaging Host。
- 对真实 Chrome 标签执行定位、打开和恢复整组。
- Developer ID 正式签名、公证与自动更新。

这些项目都需要用户单独授权。它们不影响当前模拟数据、模型校验、静态安全、视觉与资源占用结论。
