# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库性质

- **Magpie**：本地优先、键盘驱动的 macOS 剪切板管理器，目标替代 Maccy + Deck，开源协议 MIT。
- 当前阶段：**pre-alpha / v0.1 骨架**。Xcode 工程尚未落地（依赖完整 Xcode，详见「如何运行」）。
- 已完成 `git init`，但 `git push` 与公开仓库待 v0.1 跑通后再做。
- 中文协作：目录与说明文档含中文，命令行操作含中文路径必须双引号。

## 仓库结构

```
magpie/
├── Magpie.xcodeproj/         # Swift 工程（Phase 0b 待建）
├── Sources/                  # Swift 源码（App / Panel / Clipboard / Storage / Paste / Hotkey）
├── Resources/                # Info.plist / Assets.xcassets
├── prototype/                # 原始 React/JSX 浏览器原型 + 设计规格说明（仅作设计参考）
│   └── 剪切板工具/
│       ├── Deck Clipboard.html
│       ├── Magpie 原型说明.html   # 13 节完整设计规格 — 事实标准
│       ├── *.jsx / styles.css
├── md/                       # 笔记/计划/记忆/ADR（软链到 ~/work/code/sanwan/notes/magpie/md/）
├── README.md                 # 开源用 README
├── LICENSE                   # MIT
└── CLAUDE.md                 # 本文件
```

`md/` 是软链，物理落在 `~/work/code/sanwan/notes/magpie/md/`（私人 notes 仓 `git@github.com:sanwan99/notes.git`）。`.git/info/exclude` 已排除 `/md`，主仓 git 看不到笔记内容。

## 技术栈与构建

- 语言：Swift 5.9+ / SwiftUI（部分 AppKit 桥接：NSPanel / NSVisualEffectView / NSPasteboard）
- 部署目标：macOS 14+
- 工具链：**完整 Xcode**（Command Line Tools 不够）。检查：`xcode-select -p` 应输出 `/Applications/Xcode.app/Contents/Developer`。
- 关键依赖（SPM）：[`HotKey`](https://github.com/soffes/HotKey)、[`GRDB.swift`](https://github.com/groue/GRDB.swift)；v0.2 起加 `KeyboardShortcuts`，v0.3 起加 `Sparkle`。
- 选型决策见 `md/codex/plan/decisions/0001-tech-stack-swiftui.md`（ADR-0001）。

构建（Phase 0b 落地后）：

```
open Magpie.xcodeproj
# Build & Run (⌘R)
```

## 设计依据

`prototype/剪切板工具/Magpie 原型说明.html` 是 13 节完整设计规格（产品定位 → 信息架构 → 数据模型 → 组件 → 交互 → 快捷键 → 搜索 → 三种布局 → 设置 → Snippets → 视觉规范 → 技术建议 → 实现路线）。**任何关于交互、键位、布局、视觉、命名隐喻的细节，先查这份文档再改代码**；要偏离规格，先在 ADR 里记录决策。

关键约束（来自规格，落地必须遵守）：

- **本地优先 / 隐私第一**：永不联网、不上传、不分析。`Send analytics` 永不开。
- **键盘是一等公民**：每个鼠标可达功能必须有快捷键。完整键位见规格 §06。
- **视觉极简**：黑白灰为主，accent 限定 mono / graphite / blue / olive；不引入花哨配色或品牌渐变。
- **类型即视觉**：6 种类型（text / code / url / image / file / folder）各有专门预览。

## prototype/ 的角色

`prototype/剪切板工具/` 下的 `*.jsx`、`styles.css`、`Deck Clipboard.html` 是早期浏览器原型，**只作视觉/交互规范的参考**，不是要复用的代码。SwiftUI 实现要按规格说明从头来，不机械翻译 React 组件。

如果要在浏览器里再次跑原型作视觉对照：

```
open "prototype/剪切板工具/Deck Clipboard.html"
```

不要在原型上再做新功能。新功能直接在 SwiftUI 工程里做。

## 项目记忆与文档入口

- `md/00-文档导航.md` —— 全部 md 文档入口
- `md/codex/README.md` —— 任务归档（plan / changelog / decisions / ledger）
- `md/codex/current/` —— 当前活跃任务面板
- `md/codex/plan/tasks/2026-04-25-v0.1-skeleton-plan.md` —— v0.1 任务计划
- `md/codex/plan/decisions/0001-tech-stack-swiftui.md` —— ADR-0001 技术栈选型
- `md/memory/00-总索引.md` —— 项目长期记忆
- 全局项目入口：`~/.codex/memories/ai全局管理/projects/magpie/00-总索引.md`

笔记 git 操作走 notes 仓：`git -C ~/work/code/sanwan/notes <cmd>`。一个任务一个 commit，commit 粒度对齐 changelog/ledger 节奏。

## 与用户协作的注意事项

- 中文沟通；含中文路径必须双引号。
- 危险操作一律先确认：删除文件/目录、改动 `prototype/` 内容、任何 `git push`、`git reset --hard`、依赖大版本升级、生产 API 调用、全局工具卸装。
- 不引入 Tauri / Electron / 跨平台层（已通过 ADR-0001 排除）。
- 不引入 Tailwind / CSS-in-JS / 预处理器（项目用 SwiftUI，原 styles.css 仅作视觉参考）。
- 测试：单元测试在 Xcode 工程内 `XCTest`；后台跑测试单次不超过 60 秒。
- 提交规范：Conventional Commits；正文说明影响范围与验证方式。
