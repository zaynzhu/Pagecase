<div align="center">

<img src="artifacts/pagecase-icon.png" alt="页匣应用图标" width="148">

# 页匣 · Pagecase

网页离开内存，不离开手边。

[核心能力](#-核心能力) · [开始使用](#-构建与连接) · [安全边界](#-安全边界) · [项目文档](#-文档)

</div>

<div align="center">

[中文](README.md) | [English](README_EN.md)

</div>

<div align="center">

![Version](https://img.shields.io/badge/version-0.7.0-2F3437?style=flat-square)
![macOS](https://img.shields.io/badge/macOS-14%2B-787774?style=flat-square&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-D97757?style=flat-square&logo=swift&logoColor=white)

</div>

> [!TIP]
> 页匣是一款为低内存 Mac 设计的本地网页资料库。Chrome 现场可以实时镜像并保存快照；Safari 当前窗口可以在需要时一次性收纳成合集。两种浏览器在界面与数据中明确分开，需要时再统一搜索。

![Chrome 与 Safari 清晰分区](artifacts/qa-browser-separation.png)

---

## ✨ 核心能力

- **实时镜像 Chrome** — 展示普通窗口、原生标签组、未分组网页和原有顺序，不读取网页正文。
- **按需收纳 Safari** — 只在点击时读取 Safari 最前方窗口，核对后保存为本地合集；无需 Safari 扩展、完整 Xcode 或后台监测。
- **浏览器明确分区** — 侧栏、资料库、数量、图标、动作与结果提示都区分 Chrome 和 Safari；进入另一浏览器页面后不会串入上一方的反馈。
- **按现场或分组保存** — 可以保存完整 Chrome 现场，也可以只保存一个标签组；两者写入后都不会被后续变化改写。
- **判断是否放心关闭** — 实时显示完整现场和每个标签组的保存覆盖状态，并可直接切换“全部 / 需保存 / 已收纳”。
- **确认收纳是否生效** — Chrome 快照会显示还有多少保存网页仍在 Chrome，以及保存时的原标签组是否仍存在；来源过期时不会猜测。
- **快速找回网页与分组** — 搜索标题、域名、完整网址、标签组和快照名称，并可明确切换“全部 / Chrome / Safari”；标签组作为独立结果，可直接查看或从快照确认恢复。
- **按需恢复** — 定位仍在 Chrome 中的网页、从快照打开单页，或按原顺序恢复完整标签组。
- **保留整理语境** — 保存窗口、组名、颜色、顺序和重复网址，不把不同语境中的相同网址强行去重。
- **版本序列收纳** — 同一标签组的多次保存折叠为一个版本序列，最新版优先，旧版本仍可展开、重命名或删除。
- **本地资料管理** — 支持带确认的删除、完整资料库备份、浏览器分区导出，以及确认前只读的 Chrome / Safari 导入预览。
- **原生且轻量** — 使用 SwiftUI、AppKit 与极小的 Manifest V3 连接器，不使用 Electron、WebView、数据库或云服务。

---

## 🚀 核心流程

页匣解决的是“关闭后还能不能找回来”，不会替你自动清理浏览器。

Chrome：

1. 在“现在”页面切到“需保存”，逐组保存准备关闭的标签组；也可以保存完整现场。
2. 回到 Chrome，由你自己关闭暂时不用的页面或标签组，释放内存。
3. 以后通过搜索打开一个网页，或从快照恢复整个标签组。

恢复整组前，页匣会显示目标 Chrome 来源、组内网页数、当前已打开的相同网址数量和将新建的标签数，并提醒恢复期间内存可能短时上升。重复网址不会自动去重；连接器只组合本次恢复命令新建的标签，不会把任何已有标签加入新组。执行后会保留一张 Chrome 专属恢复回执，明确区分完整成功、部分完成、失败和超时；部分完成或超时都不会自动清理、重试或制造第二份标签。

Safari：

1. 在 Safari 打开准备收纳的原生标签组，让它位于最前方。
2. 在页匣进入“Safari · 按需收纳”，点击“读取当前窗口”，核对预览后命名保存。
3. 确认可搜索、可打开后，由你自己关闭 Safari 原标签组。

Safari 读取完成即停止，不会持续监听。由于系统自动化接口无法可靠提供原生标签组名称，合集名称由你在页匣中填写。

---

## 📦 构建与连接

### 系统要求

- macOS 14 或更高版本
- Google Chrome；使用 Safari 合集时需要系统自带 Safari
- Swift 6 与 Apple Command Line Tools
- Node.js 22，仅在运行扩展测试时需要

### 从源码构建

```bash
git clone https://github.com/zaynzhu/Pagecase.git
cd Pagecase
./scripts/build-app.sh
open "dist/页匣.app"
```

构建脚本会生成经过 ad-hoc 签名的 `dist/页匣.app`，并把 Chrome 连接器与 `PagecaseBridge` 一同打包。构建与 Safari 按需收纳都不需要完整 Xcode。

### 首次连接 Chrome

1. 打开页匣的“设置”，点击“显示扩展文件”。
2. 在 Chrome 地址栏打开 `chrome://extensions`，启用“开发者模式”。
3. 点击“加载已解压的扩展程序”，选择页匣刚显示的文件夹。
4. 复制 Chrome 显示的 32 位扩展标识，粘贴回页匣。
5. 点击“配置本地连接”，等待“已连接”状态出现。

页匣不会替你打开扩展管理页，也不会自动安装扩展。需要排查时，可查看连接器文件夹中的 `README.txt`。

---

## 💡 使用方式

### 保存当前现场

进入“现在”，选择 Chrome 来源并点击“保存当前现场”。快照会完整复制当时的窗口和分组结构，保存成功后显示网页数、标签组数和覆盖状态。

### 单独保存一个标签组

每个标签组会显示自己的保存状态：

- “保存该组”只复制当前标签组，不保存其他窗口或网页。
- 组内新增网页后显示未保存数量，并提供“保存最新版本”。旧版本继续保留，不会被覆盖。
- 已完整保存的标签组提供“查看快照”，直接打开对应版本和标签组。

标签组快照保留组名、颜色、网页顺序和重复网址。完整现场状态只由完整现场快照判断，避免把一份标签组快照误认为整个 Chrome 已经保存。

![单个标签组保存状态](artifacts/qa-group-save-states.png)

### 筛出下一批要收纳的标签组

“现在”页面会汇总已收纳标签组数量，并提供三种平直筛选：

- “全部”保留原窗口结构，也继续显示未分组网页。
- “需保存”只显示尚未完整进入本地快照的标签组，保存成功后会立即从这一栏移出。
- “已收纳”只显示当前内容已完整保存在本地快照中的标签组，可直接查看对应快照。

“已收纳”不是自动关闭许可。确认快照可用后，仍由你回到 Chrome 手动关闭不常用的标签组。若从搜索打开一个被当前筛选隐藏的组，页匣会先回到“全部”再定位，避免目标消失。

![Chrome 标签组收纳筛选](artifacts/qa-group-readiness.png)

### 确认后再关闭 Chrome 标签组

当 Chrome 来源仍然新鲜、某个标签组的网页又已经全部写入同一来源的本地快照时，“现在”页面会在筛选条下方显示“可以手动关闭”清单。清单会保留窗口编号、标签组名称、网页数量、对应快照和最近保存日期，并提供“定位”入口，方便你在关闭前做最后一次核对。

这是一份安全提示，不是浏览器操作权限：页匣不会替你关闭、移动、挂起或重新分组任何标签。确认无误后，回到 Chrome 手动关闭对应标签组，完成释放内存的动作。清单只属于 Chrome 当前页；Safari 页面不会出现这段文案、Chrome 在场状态或关闭语义。

![Chrome 可以手动关闭清单](artifacts/qa-chrome-closable-groups.jpeg)
![Chrome 可以手动关闭清单深色模式](artifacts/qa-chrome-closable-groups-dark.jpeg)

### 浏览标签组的历史版本

同一个 Chrome 标签组反复保存后，快照侧栏会把这些独立快照收纳到一个版本序列：

- 版本序列默认折叠并直接打开最新版，不让旧版本挤满侧栏。
- 点击箭头可以展开较早版本；每个版本仍保留自己的名称、日期、网页数量和完整内容。
- 完整现场快照始终独立显示；标签组名称或颜色改变后也会形成新的版本序列。
- 重命名或删除只影响当前选中的快照，不会合并、覆盖或自动清理其他版本。

![标签组版本序列](artifacts/qa-snapshot-series.png)

### 确认网页是否已经离开 Chrome

打开 Chrome 快照后，标题下方会显示这份快照中的网页还有多少仍存在于同一个 Chrome 来源；每个标签组旁会进一步显示保存时的原标签组是否仍存在，以及组内还剩多少保存网页。重复网址按实际数量核对，不会把一个页面重复计算多次。

快照索引顶部的“收纳总览”会汇总已离开、部分仍在、全部仍在和待确认的快照数量。标签组恢复成功后，扩展还会返回本次创建的新组标识；页匣将它单独保存在本机，之后会把状态显示为“已恢复为新组”，而不是继续把新组误认成已经离开的原组。

- “全部仍在 Chrome”表示这些保存网页仍全部打开。
- “N / M 仍在 Chrome”表示只有一部分仍打开。
- “已离开 Chrome”表示这些网页目前只保存在本地快照中。
- “暂时无法确认”表示原 Chrome 来源未连接或实时数据过期，页匣不会据此猜测关闭结果。

这组状态只属于 Chrome 快照。Safari 合集没有后台实时来源，因此不会显示 Chrome 在场状态，也不会被拿来参与判断。状态只帮助你核对结果，关闭操作仍由你在浏览器中完成。

![Chrome 快照在场状态](artifacts/qa-chrome-presence-mixed.png)

![Chrome 收纳总览与恢复新组状态](artifacts/qa-chrome-overview-restored-group.jpg)

### 收纳 Safari 当前窗口

1. 先在 Safari 切换到目标标签组或窗口。
2. 在侧栏的 Safari 区域点击“按需收纳”，再点击“读取当前窗口”。
3. 核对页面顺序、重复网址、当前页和跳过数量，点击“保存为合集”并命名。
4. 在 Safari“合集”中浏览、删除、打开单页，或确认数量后“在 Safari 打开全部”。

![Safari 按需收纳](artifacts/qa-safari-import.png)

Safari 合集不会假装是 Chrome 快照，也不会反向修改 Safari。系统首次读取时可能询问自动化权限；拒绝权限不会影响 Chrome 功能。

### 搜索并找回网页或标签组

按 `⌘K` 输入标题、域名、网址、标签组或快照名称：

- 结果顶部可以切换“全部 / Chrome / Safari”；顶栏同步显示当前搜索范围，切换后不会混入另一浏览器内容。
- 浏览器专属提示跟随当前页面与搜索范围显示；Chrome 和 Safari 的结果不会跨区延续。
- 实时结果使用“定位”，只聚焦已经打开的标签。
- 快照结果使用“打开”，只新建一个标签。
- 标签组结果使用“查看”，只在页匣内打开并展开对应位置；快照标签组另有“恢复整组”，核对专属预览后才会创建标签。
- Return 对标签组执行“查看”，不会直接恢复整组。
- 来源离线或数据过期时，相关动作会禁用，但本地快照仍可浏览和搜索。

![按浏览器筛选搜索结果](artifacts/qa-search-browser-filter.png)

### 恢复或删除快照内容

- 在快照标签组标题右侧点击“恢复整组”，先核对来源、已有相同网址、将新建数量和内存提示，再按原顺序创建并组合新标签。
- 恢复回执显示已创建／应创建数量、是否成组和失败阶段；部分完成或超时时先核对 Chrome，页匣不会自动回滚或重试。
- 在快照详情标题旁点击“删除快照”，确认名称和网页数量后才会删除对应的本地文件。
- 删除快照无法撤销，但不会关闭或改变 Chrome 中的任何页面。

![Chrome 标签组恢复预览](artifacts/qa-group-restore-preview.png)

![Chrome 标签组恢复回执](artifacts/qa-restore-receipt-success.png)

---

## 🔒 安全边界

> [!IMPORTANT]
> 页匣不会自动关闭、移动、挂起、解除分组或重新分组任何已有 Chrome 或 Safari 标签。真正释放内存的关闭操作始终由用户本人完成。

页匣明确不做以下事情：

- 不读取网页正文、截图、浏览历史、书签、下载记录或无痕窗口。
- 不处理 `file://`、`chrome://`、扩展页或其他非 Web 协议。
- 不登录、不联网、不上传遥测，也不提供账号、云同步或团队协作。
- 不使用 Chrome 标签关闭、移动、挂起或解除分组 API。
- 不自动恢复窗口，不修改任何已有标签组。
- 不后台监测 Safari，不读取 Safari 原生标签组名称，也不执行网页脚本或读取网页正文。

所有会改变 Chrome 可见状态的操作都来自用户单次点击；恢复整组还需要在专属预览中核对来源、数量和重复网址提示。详细边界见 [产品设计](docs/PRODUCT.md) 与 [架构决策](docs/adr/0002-restore-groups-with-new-tabs-only.md)。

---

## 技术架构

```mermaid
flowchart LR
    Chrome --> Connector["Pagecase Connector"]
    Connector -->|"Native Messaging"| Bridge["PagecaseBridge"]
    Bridge --> JSON["Versioned local JSON"]
    App["PagecaseApp"] --> JSON
    Safari -->|"点击后读取一次"| App
    App -->|"确认后保存合集"| JSON
    App --> Commands["Explicit commands"]
    Commands --> Bridge
```

| 组件 | 职责 |
|---|---|
| `PagecaseApp` | SwiftUI/AppKit 原生界面、搜索、快照、Safari 按需捕获、设置与菜单栏入口 |
| `PagecaseCore` | 数据模型、校验、原子 JSON 存储、覆盖判断与命令模型 |
| `PagecaseBridge` | Chrome Native Messaging 协议、实时现场落盘与命令转发 |
| `extension/` | 查询普通 Chrome 窗口和标签组，执行严格白名单命令 |

应用运行时没有第三方依赖，也不启动本地 HTTP 服务。

---

## 本地数据

正式模式的数据默认保存在：

```text
~/Library/Application Support/Pagecase/
├── live/
├── snapshots/
├── preferences.json
└── ChromeExtension/
```

Chrome 快照与 Safari 合集共同存放在 `snapshots/`，每份 JSON 都持久保存浏览器种类与来源名称；应用会按来源分区。设置中既可导出完整资料库，也可单独导出 Chrome 快照或 Safari 合集，单独导出的文件不会混入另一浏览器。文件包含完整网址，其中可能带有敏感查询参数，备份或分享前请按浏览数据妥善保管。

导入资料库时，页匣会先完整校验文件并打开只读预览：Chrome 快照与 Safari 合集分成两行，各自显示资料、网页、标签组和标识冲突数量。可以取消任一浏览器来源；确认前和取消后都不会写入资料，冲突记录只会另存为副本。

![Chrome 与 Safari 分区导入预览](artifacts/qa-import-preview.png)

---

## 🧪 开发与验证

使用隔离演示数据启动应用，不连接真实 Chrome：

```bash
PAGECASE_DEMO=1 \
PAGECASE_DATA_ROOT="$(mktemp -d)/pagecase" \
"dist/页匣.app/Contents/MacOS/PagecaseApp" --demo
```

运行完整自动化检查：

```bash
swift build
swift test --enable-swift-testing --disable-xctest
swift run PagecaseCoreChecks
npm run check:extension
npm run test:extension
npm run test:bridge
./scripts/validate-extension.sh
npm run check:safari
./scripts/build-app.sh
```

仓库内置 [GitHub Actions 项目检查](.github/workflows/quality.yml)：推送到 `main`、提交 Pull Request 或手动触发时，使用标准 `macos-15` runner 执行同一组 Swift、扩展、Safari 边界、Release 与 Bridge 检查。工作流只有代码读取权限，不上传构建产物，也不会连接真实 Chrome 或 Safari。

当前 0.7.0 版本已通过 111 项 Swift 核心行为检查、13 项扩展测试、Bridge 结构化结果往返、Chrome 扩展与 Safari 捕获静态安全检查、Release 构建、浅深色视觉验收和 500 页性能验收；Chrome“可以手动关闭”清单只提供核对与定位，不会替用户关闭标签。

> [!NOTE]
> 仅安装 Command Line Tools 的环境无法正常枚举 Swift Testing 测试；`swift test` 仍负责编译测试包，`PagecaseCoreChecks` 会实际执行同一组关键行为检查。

---

## 📚 文档

| 文档 | 内容 |
|---|---|
| [产品设计](docs/PRODUCT.md) | 产品目标、范围、关键流程与失败场景 |
| [技术架构](docs/ARCHITECTURE.md) | 组件边界、数据协议、存储和安全约束 |
| [视觉设计](docs/VISUAL-DESIGN.md) | 原生 macOS 界面规范与交互细节 |
| [验证计划](docs/VALIDATION.md) | 自动化、静态安全、视觉与性能验收要求 |
| [验证结果](docs/VALIDATION-RESULTS.md) | 当前版本的完整验收记录与未验证项 |
| [ADR 0001](docs/adr/0001-native-app-with-read-only-chrome-bridge.md) | 原生应用与 Chrome 桥接架构决策 |
| [ADR 0002](docs/adr/0002-restore-groups-with-new-tabs-only.md) | 只用新建标签恢复完整分组的安全决策 |

---

## 🤝 参与开发

项目遵循小步、原子提交和可验证改动。提交前请至少运行与变更相关的 Swift 或 Node 测试；如果修改扩展命令，还必须运行 `./scripts/validate-extension.sh`。

```bash
git clone https://github.com/zaynzhu/Pagecase.git
cd Pagecase
swift build
swift run PagecaseCoreChecks
npm run test:extension
```

提交信息使用 `type: 中文描述` 格式，例如 `feat: 添加快照筛选` 或 `fix: 修复来源状态判断`。
