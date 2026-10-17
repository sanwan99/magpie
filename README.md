<div align="center">
<img src="docs/screenshots/logo.png" alt="Magpie Logo" width="160" />

# Magpie

**把复制过的好东西，随手找回来。**

本地优先、键盘驱动的 macOS 剪贴板与截图工具。保存历史、快速搜索、复用片段，再把内容贴回正在工作的窗口。

*A local-first clipboard and screenshot companion for macOS.*

**简体中文** · [English](README_EN.md)

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)](#从源码构建)
[![MIT License](https://img.shields.io/badge/License-MIT-blueviolet)](LICENSE)
[![Release: Source Alpha](https://img.shields.io/badge/Release-Source%20Alpha-orange)](https://github.com/sanwan99/magpie/releases)
[![macOS CI](https://github.com/sanwan99/magpie/actions/workflows/ci.yml/badge.svg)](https://github.com/sanwan99/magpie/actions/workflows/ci.yml)

</div>

## 应用截图

![Magpie 的 Splat 主题与 Grid 布局](docs/screenshots/panel-splat.png)

仓库现有版本的真实截图，展示 Splat 主题、类型筛选、网格卡片和详情预览；不代表新增设置页的最终外观。

## 核心功能

- **随时暂停**：菜单栏可暂停记录 15 分钟／1 小时、提前恢复，或直接忽略当前应用。暂停状态跨重启保留，恢复时不补录暂停期间的内容。
- **剪贴板历史**：文本、代码、链接、图片、文件、文件夹，按类型预览。复制的文件只记录路径，不复制原文件。
- **搜索与整理**：FTS5 全文搜索，中文子串回退；支持 `type:code`、`app:vscode`、引号短语及组合查询。可置顶、写备注、设置保留天数和数量。
- **键盘操作**：默认 `⌘P` 呼出面板，`↩` 或 `⌘1–9` 粘贴；全局面板／截图快捷键可在设置中修改。Queue Mode 支持连续取用。
- **Snippets**：保存常用文字模板；可选快捷字符串展开。隐私锁开启时自动展开暂停，避免绕过面板认证。
- **截图编辑**：默认 `⌘J`；框选、窗口选择、箭头、文字、马赛克、撤销、PNG 保存、OCR、悬浮贴图和手动滚动长截图。自动打码后仍需人工检查。
- **原生外观**：Stripe／Stack／Grid 三种布局，Mono／Graphite／Blue／Olive／Splat 五种主题，中英文界面。macOS 26 使用原生玻璃效果；旧系统使用兼容材质。

列表默认最多展示 200 个匹配项，不会一次加载整个历史库。图片、文件、文件夹各保留最近 50 条非置顶记录；置顶项不受自动保留上限影响。

## 下载与安装

**当前为 Source Alpha，尚无已发布、可供普通用户下载安装的正式 Release。**

[GitHub Releases](https://github.com/sanwan99/magpie/releases) 是未来发行包的唯一仓库下载入口。仓库内没有可下载的 `dist/*.dmg`；不要把源码 ZIP 当成应用安装包。希望直接双击安装的用户，建议等待经过 Developer ID 签名和 Apple 公证的发行包。

开发者和愿意自行构建的用户可按下文运行源码。默认本机构建使用 ad-hoc 签名，不需要购买开发者账户或创建个人证书；它不等于经过公证的公开发行版本，系统权限授权也可能随重建而变化。

不要关闭 Gatekeeper、SIP 或批量移除隔离属性。若系统阻止运行下载的应用，先核对来源、签名和对应版本的发布说明；不要用“绕过安全检查”作为安装步骤。

已有签名发行包时，可使用 `Scripts/install-release.sh /path/to/Magpie.app --team-id 发行说明中的团队ID` 安装（首次公开安装必须核对团队 ID）。脚本校验 Developer ID、Gatekeeper 和升级前后的团队身份，升级前备份旧应用，启动检查失败时尝试回滚。它不下载应用，不生成开发证书，不重置系统权限；当前没有发行包可用于验证完整公开安装流程。该可选脚本需要 Python 3；未来正式 DMG 应同时提供 Finder 拖拽安装方式。

## 首次使用

1. 首次启动会显示“使用入门与权限”，说明本地数据与权限用途；点击“开始使用”后不再自动显示，也可随时从菜单栏重新打开。Magpie 不常驻 Dock。
2. 复制一段普通文字，按 `⌘P` 或从菜单栏打开面板。启动前已经在剪贴板里的内容不会自动导入。
3. 选择记录并按 `↩`。自动粘贴需要辅助功能权限；未授权时仍可复制记录后手动 `⌘V`。
4. 在“历史”中设置保留时间和忽略的应用；在“隐私”中按需打开认证锁。
5. 若 `⌘P`／`⌘J` 与其他应用冲突，从“快捷键”更换组合。Carbon 报告的冲突会阻止保存；系统保留快捷键还需在系统设置中检查。

| 权限或系统能力 | 用途 | 是否必需 |
| --- | --- | --- |
| 辅助功能 | 将内容自动贴回目标窗口、可选片段展开 | 自动粘贴必需；历史浏览不需要。仅在入门页主动点击授权时请求 |
| 输入监控 | 可选的全局片段触发监测，实际授权行为由 macOS 决定 | 基础历史功能不需要 |
| 屏幕录制 | 用户主动发起截图、长截图 | 截图必需；不录制音频 |
| 系统认证 | Touch ID／macOS 账户密码回退 | 仅开启隐私锁时使用 |

粘贴前会重新检查目标应用、窗口、剪贴板版本及权限。目标退出、焦点改变或窗口无法可靠识别时会取消，并显示不抢焦点的原因提示；内容仍在剪贴板时可手动粘贴。若剪贴板已被替换，会提示重新选择记录，不会建议粘贴旧内容。

## 常用快捷键

| 范围 | 默认快捷键 | 操作 |
| --- | --- | --- |
| 全局 | `⌘P` / `⌘J` | 显示／隐藏面板；截图（均可自定义） |
| 面板 | `↩` / `⌘1–9` | 粘贴选中项／指定项 |
| 面板 | 方向键 / `Space` / `⌘O` | 选择记录／详情／独立预览 |
| 面板 | `⌘D` / `⌘S` / `⌘Q` | 置顶／片段抽屉／Queue Mode |
| 面板 | `⌘\` / `⌘,` / `Esc` | 切换布局／设置／逐级取消 |
| 截图 | `V R O A P T M E` | 选择、矩形、椭圆、箭头、画笔、文字、马赛克、表情 |
| 截图 | `X L D N G` | OCR、系统翻译、自动打码、贴图、长截图 |
| 截图 | `⌘Z` / `⇧⌘Z` | 撤销／重做 |
| 截图 | `↩` / `⌘C` / `⌘S` / `Esc` | 复制／复制／保存 PNG／取消 |

[完整截图操作说明](docs/SCREENSHOTS.md)。截图按当前显示器处理，暂不支持跨屏拼接。

## 隐私与安全

- **数据位置**：`~/Library/Application Support/Magpie/clips.sqlite` 保存历史、索引和 Snippets；图片在同目录的 `images/`；偏好使用 UserDefaults。安装脚本的应用备份位于 `Backups/`。
- **尚未加密**：使用普通 SQLite，未集成 SQLCipher。目录／文件权限限制其他系统用户，但不能阻止同一账户下有权限的进程或管理员读取。隐私锁保护面板访问，不是数据库加密。
- **敏感内容过滤**：始终跳过 Concealed／Transient 等标记；可选规则尝试识别常见 API key、Bearer、JWT、私钥和带上下文的验证码。规则可能漏判或误判，不能识别任意密码或图片中的秘密。忽略来源应用也是基于复制时观察到的前台应用，不能替代系统隐私标记。
- **认证周期**：每次重新打开隐藏的面板都需要系统认证；隐藏、休眠、锁屏、切换会话或重启后重新锁定。认证失败、取消或系统策略不可用时不放行；更改锁开关也需认证。
- **网络边界**：当前应用未实现遥测、账户或云同步，也未接入云端 OCR／翻译 API。OCR 在本机运行；macOS 翻译可能按用户操作下载语言包，系统服务自身行为由 Apple 管理。系统分享由用户选定服务处理；打开链接会交给默认应用。开发脚本 `generate-theme-mascots.py` 可主动调用外部图片 API，不属于应用运行流程。
- **暂停边界**：暂停同时阻止自动记录和截图加入历史，仍可复制／保存截图及使用已有历史。暂停不删除已有记录，也不撤销已经开始的写入；排队尚未开始的旧快照会失效。忽略应用按打开菜单时识别的应用保存，可在“历史”中移除。
- **清理边界**：“清空所有剪贴板记录”删除历史、置顶、FTS 记录和受管理的图片缓存；保留 Snippets、设置、系统剪贴板、应用备份及用户原文件。删除是逻辑删除，不保证清除 SQLite WAL、空闲页、系统快照、Time Machine 或其他备份中的旧字节。

发现安全问题请阅读 [SECURITY.md](SECURITY.md)。报告中不要粘贴真实密码、Token 或私人剪贴板内容。

## 从源码构建

运行要求：**macOS 14+**。当前源码和全部测试使用 **完整 Xcode 26+**（含 macOS 26 SDK），仅 Command Line Tools 不够。翻译需 macOS 15+；原生玻璃需 macOS 26+。Swift 使用 5.9 语言模式；唯一 SPM 依赖是 [GRDB.swift](https://github.com/groue/GRDB.swift)。

```bash
git clone https://github.com/sanwan99/magpie.git
cd magpie
xcodebuild -version
Scripts/build-local.sh
```

工程已提交，普通构建不需要 XcodeGen。首次构建由 Swift Package Manager 获取 GRDB。脚本会打印本地 `.app` 路径及显式安装命令；只对自己审查并构建的源码使用 `--local-build`。

若需长期稳定的本机签名，可自行选择已有签名身份：

```bash
MAGPIE_CODE_SIGN_IDENTITY='Your local signing identity' Scripts/build-local.sh
```

`python3 Scripts/setup-local-signing.py --create` 是可选开发工具，会创建本机证书及钥匙串条目，不是普通用户或 CI 的安装前置条件。公开发行必须另用 Developer ID 签名与公证。

修改工程定义后，通过 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 重新生成，并提交 `project.yml` 和工程文件：

```bash
brew install xcodegen
xcodegen generate
```

## 开发与测试

```bash
Scripts/test.sh
python3 -m unittest discover -s Tests/Tooling -v
python3 Scripts/check-privacy-logs.py
python3 Scripts/check-doc-links.py
python3 Scripts/benchmark-storage.py
```

`Scripts/test.sh` 执行完整 XCTest，使用独立临时 DerivedData，并在 `.build/` 写入 `.xcresult`。CI 在 macOS 上构建 Release 配置并运行同一测试入口，不读取个人开发证书。

真实屏幕捕获与已安装语言包测试有环境条件；原有测试会在条件不满足时报告原因，不能把这些跳过算作通过。安装事务测试模拟系统命令，不能代替真实 Gatekeeper／Touch ID／多窗口粘贴验收。

[本次审查与验证记录](docs/review/2026-10-18.md) · [性能方法与数据](docs/PERFORMANCE.md) · [发布与人工验收清单](docs/RELEASING.md)

## Roadmap

- **当前 Source Alpha**：剪贴板、搜索、Snippets、主题、截图编辑及隐私／稳定性修复。
- **下一候选版本 `v0.4.0-alpha.1`**：完成真实 macOS 权限、签名、公证、干净安装与升级验收后，再决定是否发布预发行包。这个标签尚未发布。
- **后续评估**：本地数据加密、受签名保护的自动更新、中文搜索扩展、复杂长截图稳定性。没有已交付或固定日期的承诺。

## Contributing

欢迎小范围、可验证的修复。先读 [贡献指南](CONTRIBUTING.md)；`project.yml` 定义工程，当前代码与测试定义已实现行为，`prototype/` 只供设计参考。PR 请写明问题、变化、验证结果和用户可见的影响。

Magpie 保留 SwiftUI + AppKit + GRDB + SQLite 技术栈，不计划引入跨平台壳或重写应用。

## License

[MIT](LICENSE) © 2026 sanwan99 and Magpie contributors。

Splat 是受游戏喷墨风格启发的主题；本项目与 Nintendo 无关联或背书。公开发行前仍需核对品牌素材及截图中第三方内容的再分发权利。
