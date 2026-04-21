# macOS Window Reopen Behavior

## Status

Accepted

## Date

2026-04-18

## Context

`Noter` 是一个 macOS 原生单主窗口应用。用户按下窗口左上角红色关闭按钮后，应用本身不会退出，但如果随后点击 Dock icon 无法重新打开主窗口，体验会明显偏离 Chrome、Terminal、Finder 等常见 macOS 应用。

这类问题通常不是系统 bug，而是应用没有把「最后一个窗口被关闭后，用户重新点 Dock icon」这条生命周期补完整。

## Decision

- 主界面使用单主窗口语义。
- 关闭最后一个窗口后，应用保持运行。
- 用户点击 Dock icon 重新打开应用时，如果当前没有可激活窗口，应用必须重新打开主窗口，而不是要求用户先 Quit 再启动。
- 自定义 `NSApplicationDelegate` 时，必须显式处理 `applicationShouldHandleReopen`，并通过 scene-aware 的 `openWindow(id:)` 恢复主窗口。

## Consequences

- 应用的窗口行为更接近原生 macOS 预期。
- 红色关闭按钮、黄色最小化按钮、Dock icon 重开这三条路径会各自保持清晰语义。
- 以后如果继续用 Codex 开发 macOS app，需要把这条窗口生命周期当作默认要求，而不是额外增强项。
