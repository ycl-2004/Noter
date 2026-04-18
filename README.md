# Noter

`Noter` 是一个用 SwiftUI 开发的 macOS 笔记整理应用。它的目标不是单纯把文字收进一个编辑器，而是把用户贴进来的原始资料、上传的文件、图片里的 OCR 文本，整理成可继续编辑、可套用模板、可导出成正式文档的结构化内容。

目前这个项目主要在做三件事：

1. 帮用户把杂乱资料快速整理成有结构的笔记或文稿。
2. 让用户可以在应用里继续编辑、预览、套模板、对比优化版本。
3. 把最终内容稳定导出成 Markdown、DOCX、PDF 等可交付格式。

## 这个项目现在已经能做什么

### 1. 从原始资料生成结构化内容

- 支持贴入文本或导入文件作为输入。
- 支持从图片里提取 OCR 文本。
- 长文本会自动分块、摘要、合并，再生成最终草稿。
- 可以输出为笔记、总结、正式文稿、行动项等不同结构。

### 2. 多阶段工作流

应用内目前采用一条完整的工作流：

1. `Intake`
2. `Processing`
3. `Edit`
4. `Preview`
5. `Export`

这条流程的重点是先尽快给用户一个可编辑版本，再在后台继续做 refinement，而不是让用户一直干等。

### 3. Progressive Refinement

- 先生成一版可立即编辑的草稿。
- 后台继续做 polish / repair / normalization。
- 优化后的版本会作为一个安全升级项出现。
- 用户可以选择比较、应用、或忽略，不会自动覆盖当前编辑内容。

### 4. 多模型 / 多 Provider 路由

现在已经支持多种模型与服务接法，例如：

- Local Ollama
- Custom API
- Hosted provider presets

并且支持把不同工作步骤分配给不同模型：

- 主生成模型
- 分块模型
- polish 模型
- repair 模型

根目录不会保存真实 API key。你可以在本地通过应用设置页，或环境变量来配置。

支持的环境变量包括：

- `NOTESCURATOR_NVIDIA_API_KEY`
- `NOTESCURATOR_OPENAI_API_KEY`
- `NOTESCURATOR_ZHIPU_API_KEY`
- `NOTESCURATOR_MISTRAL_API_KEY`
- `NOTESCURATOR_ANTHROPIC_API_KEY`
- `NOTESCURATOR_GEMINI_API_KEY`

### 5. 模板系统

现在项目已经有比较完整的模板能力：

- 内容模板（content template）
- 视觉模板（visual template）
- Markdown 模板渲染
- Template pack 结构
- LaTeX 模板导入

尤其是最近这轮功能，重点补强了 LaTeX 模板导入后的整条链路：

- 导入后的 pack-backed template 不会在编辑时丢失 pack data。
- imported template 的 live preview、preview、export 会尽量保持一致。
- AI 能理解更细的内容桶，例如 summary / key / meta / warning / code / result / exam / checklist / question / explanation / example。
- imported template 的 section 顺序会更贴近原始 LaTeX box 结构。
- 空 box 默认隐藏，有内容才渲染。

当前内建内容模板也开始统一到同一套 pack schema：

- 主要模板包括 `Quick Summary`、`Structured Notes`、`Lecture Notes`、`Study Guide`、`Technical Deep Dive`、`Formal Document`
- 模板尽量共享同一批内容桶，例如 `summary_boxes`、`key_boxes`、`sections`、`explanation_boxes`、`warning_boxes`、`code_boxes`
- `Formal Document` 额外强调 metadata、executive summary、目录、review questions、recommendations 这类正式交付结构
- `Study Guide` 额外强调 question / checklist 这类复习导向 box
- 每个内建模板现在也都有各自的 native sample document，preview 不再共用旧的 study-guide 数据，而是直接展示该模板自己应该出现的 box 结构与标题
- built-in preview、live preview、export 会优先走同一条 pack-backed / LaTeX-backed 原生渲染链路，而不是退回旧的 markdown fallback

### 6. 预览与导出

当前支持导出为：

- Markdown
- TXT
- HTML
- RTF
- DOCX
- PDF

这轮更新之后，PDF 导出也做了补强：

- 支持真正分页，而不是把超长视图直接硬打印成一页。
- pack-backed / imported LaTeX template 会尽量沿用当前预览中的 box/card 风格。
- 预览与导出的版式一致性已经明显提升。
- 模板库里的默认 preview 现在会用模板专属 sample blocks 去验证样式和结构，所以 preview 看到的内容更接近真实导出结果。

### 7. Workspace 与编辑体验

应用里目前已经有这些主要 UI 区域：

- Home
- Workspaces
- Drafts
- Templates
- Exports
- Settings

在单个 workspace 内，用户可以继续走完整编辑流，包括：

- source intake
- processing stages
- editor
- template selection
- preview
- export

最近也修复了一些和工作区 / 编辑界面相关的布局问题，例如 sidebar 在特定页面中位置上飘的问题。

## 项目结构

- `Sources/NotesCurator/AppModel.swift`
  应用状态、工作流调度、后台 refinement、持久化协调。
- `Sources/NotesCurator/Processing.swift`
  AI 处理链路，包括 chunking、生成、polish、repair、模型路由。
- `Sources/NotesCurator/Views.swift`
  SwiftUI 页面与交互流程。
- `Sources/NotesCurator/Models.swift`
  共享数据模型、版本、模板、导出、偏好设置。
- `Sources/NotesCurator/Providers.swift`
  不同 provider 的接线与适配逻辑。
- `Sources/NotesCurator/Exporting.swift`
  Markdown / HTML / DOCX / PDF 导出逻辑。

## 本地开发

克隆项目：

```bash
git clone https://github.com/ycl-2004/Noter.git
cd Noter
```

编译：

```bash
swift build
```

运行测试：

```bash
swift test
```

打包本地 macOS App：

```bash
./scripts/package_app.sh debug
```

打包完成后，应用会出现在：

```bash
dist/Noter.app
```

## 当前阶段的产品重点

这个项目当前不是在做一个单纯的 markdown 编辑器，而是在做一个更完整的“资料整理到正式输出”的工作台。现阶段的重点包括：

- 更稳定的多模型路由
- 更好的结构化草稿生成
- 更强的模板系统，尤其是 imported template / LaTeX template
- 让 preview、export、最终文件三者更一致
- 提升 PDF / DOCX 等正式输出的可交付质量

## 说明

这个仓库可以安全 clone 到本地运行。仓库里不包含真实 API key、用户数据库、个人缓存或本地 app bundle。要接入 hosted AI provider，请在你自己的本地环境中配置 key。
