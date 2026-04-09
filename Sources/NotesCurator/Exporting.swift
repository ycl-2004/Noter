import AppKit
import Foundation
import SwiftUI

enum ExportError: Error {
    case zipFailed
    case pdfCreationFailed
}

@MainActor
struct ExportCoordinator: Sendable {
    func previewText(draft: DraftVersion, format: ExportFormat) -> String {
        switch format {
        case .markdown:
            markdown(for: draft)
        case .txt:
            plainPreview(for: draft)
        case .html:
            htmlDocument(for: draft)
        case .rtf:
            plainPreview(for: draft)
        case .docx, .pdf:
            plainPreview(for: draft)
        }
    }

    func export(draft: DraftVersion, format: ExportFormat, to outputDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        switch format {
        case .markdown:
            return try exportMarkdown(draft: draft, to: outputDirectory)
        case .txt:
            return try exportPlainText(draft: draft, to: outputDirectory)
        case .html:
            return try exportHTML(draft: draft, to: outputDirectory)
        case .rtf:
            return try exportRTF(draft: draft, to: outputDirectory)
        case .docx:
            return try exportDOCX(draft: draft, to: outputDirectory)
        case .pdf:
            return try exportPDF(draft: draft, to: outputDirectory)
        }
    }

    private func exportMarkdown(draft: DraftVersion, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileStem(for: draft)).appendingPathExtension("md")
        try markdown(for: draft).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func exportPlainText(draft: DraftVersion, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileStem(for: draft)).appendingPathExtension("txt")
        try plainPreview(for: draft).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func exportHTML(draft: DraftVersion, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileStem(for: draft)).appendingPathExtension("html")
        try htmlDocument(for: draft).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func exportRTF(draft: DraftVersion, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileStem(for: draft)).appendingPathExtension("rtf")
        let html = htmlDocument(for: draft)
        let data = Data(html.utf8)
        let attributed = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try rtf.write(to: url)
        return url
    }

    private func exportDOCX(draft: DraftVersion, to directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let workDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let relsDirectory = workDirectory.appendingPathComponent("_rels", isDirectory: true)
        let wordDirectory = workDirectory.appendingPathComponent("word", isDirectory: true)

        try fileManager.createDirectory(at: relsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: wordDirectory, withIntermediateDirectories: true)

        let documentXML = documentXML(for: draft)
        try contentTypesXML.write(to: workDirectory.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try relsXML.write(to: relsDirectory.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try documentXML.write(to: wordDirectory.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        let destination = directory.appendingPathComponent(fileStem(for: draft)).appendingPathExtension("docx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workDirectory
        process.arguments = ["-q", "-r", destination.path, "."]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExportError.zipFailed
        }

        try? fileManager.removeItem(at: workDirectory)
        return destination
    }

    private func exportPDF(draft: DraftVersion, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileStem(for: draft)).appendingPathExtension("pdf")
        if let pack = try? draft.resolvedTemplatePackForRendering(),
           let renderedTemplate = try? draft.renderedTemplateDocument(for: .export) {
            try TemplatePackPDFRenderer(
                renderedDocument: renderedTemplate,
                pack: pack,
                contentTemplateName: draft.structuredDoc.exportMetadata.contentTemplateName.uppercased(),
                outputLanguageLabel: draft.structuredDoc.outputLanguageLabel(for: draft.outputLanguage),
                visualTemplateName: draft.structuredDoc.exportMetadata.visualTemplateName,
                pageSize: DocumentExportLayout.pageSize
            ).write(to: url)
            return url
        }

        let html = htmlDocument(for: draft)
        let data = Data(html.utf8)
        let attributed = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(
                width: DocumentExportLayout.pageSize.width - (DocumentExportLayout.pagePadding * 2),
                height: .greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        let printableHeight = DocumentExportLayout.pageSize.height - (DocumentExportLayout.pagePadding * 2)
        let pageCount = max(1, Int(ceil(contentHeight / printableHeight)))
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: DocumentExportLayout.pageSize.width, height: DocumentExportLayout.pageSize.height))

        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfCreationFailed
        }

        for pageIndex in 0..<pageCount {
            let pageOffset = CGFloat(pageIndex) * printableHeight
            let visibleRect = NSRect(
                x: 0,
                y: pageOffset,
                width: textContainer.containerSize.width,
                height: printableHeight
            )
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

            context.beginPDFPage(nil as CFDictionary?)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)
            context.saveGState()
            context.translateBy(x: 0, y: DocumentExportLayout.pageSize.height)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity

            NSGraphicsContext.saveGraphicsState()
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = graphicsContext
            let drawOrigin = NSPoint(
                x: DocumentExportLayout.pagePadding,
                y: DocumentExportLayout.pagePadding - pageOffset
            )
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: drawOrigin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawOrigin)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()

            context.endPDFPage()
        }
        context.closePDF()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExportError.pdfCreationFailed
        }
        return url
    }

    private func markdown(for draft: DraftVersion) -> String {
        renderedMarkdown(for: draft, surface: .export)
    }

    private func htmlDocument(for draft: DraftVersion) -> String {
        let document = draft.structuredDoc
        let theme = documentTheme(for: draft)
        let title = escapedHTML(document.title)
        let templateName = escapedHTML(document.exportMetadata.contentTemplateName.uppercased())
        let languageLabel = escapedHTML(document.outputLanguageLabel(for: draft.outputLanguage))
        let visualTemplate = escapedHTML(document.exportMetadata.visualTemplateName)
        let bodyHTML: String
        if let pack = try? draft.resolvedTemplatePackForRendering(),
           let renderedTemplate = try? draft.renderedTemplateDocument(for: .export) {
            bodyHTML = renderedTemplateBodyHTML(renderedTemplate, pack: pack, theme: theme)
        } else {
            let blocks = renderedBlocks(for: draft, surface: .export)
            bodyHTML = (try? MarkdownHTMLRenderer.render(blocks: blocks, theme: theme))
                ?? "<p>\(paragraphHTML(renderedMarkdown(for: draft, surface: .export)))</p>"
        }

        return """
        <!DOCTYPE html>
        <html lang="\(draft.outputLanguage == .chinese ? "zh" : "en")">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
          <style>
            :root {
              --accent: \(theme.accentHex);
              --accent-soft: \(theme.accentSoftHex);
              --surface: \(theme.surfaceHex);
              --border: \(theme.borderHex);
              --secondary: \(theme.secondaryHex);
              --body: #22304a;
              --warning: #fff4ea;
              --example: #edf8f1;
              --canvas: #ffffff;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              background: linear-gradient(180deg, #ffffff 0%, var(--surface) 100%);
              color: var(--body);
              padding: 32px;
            }
            .document {
              max-width: 860px;
              margin: 0 auto;
              background: var(--surface);
              border: 1px solid color-mix(in srgb, var(--accent) 10%, white);
              border-radius: 28px;
              padding: 28px;
            }
            .header-row, .section-title-row {
              display: flex;
              align-items: center;
              gap: 10px;
              flex-wrap: wrap;
            }
            .meta-pill {
              display: inline-flex;
              align-items: center;
              border-radius: 999px;
              padding: 6px 10px;
              font-size: 12px;
              font-weight: 700;
              letter-spacing: 0.02em;
              color: var(--accent);
              background: var(--accent-soft);
            }
            .meta-text {
              font-size: 12px;
              color: var(--secondary);
            }
            h1 {
              margin: 18px 0 14px;
              font-size: 34px;
              line-height: 1.2;
              color: var(--accent);
            }
            h2 {
              margin: 26px 0 12px;
              color: var(--accent);
              font-size: 23px;
            }
            h3 {
              margin: 18px 0 10px;
              color: var(--body);
              font-size: 18px;
            }
            .markdown-body > p,
            .markdown-body > blockquote,
            .markdown-body > ul {
              background: var(--canvas);
              border: 1px solid color-mix(in srgb, var(--accent) 12%, white);
              border-radius: 20px;
              padding: 18px;
            }
            .markdown-body > *:first-child {
              margin-top: 0;
            }
            .markdown-body > blockquote {
              border-left: 4px solid var(--accent);
              color: var(--secondary);
            }
            .template-section {
              margin-top: 26px;
            }
            .template-section:first-child {
              margin-top: 0;
            }
            .template-card {
              border-radius: 20px;
              overflow: hidden;
              border: 1px solid color-mix(in srgb, var(--accent) 10%, white);
              margin-top: 18px;
              break-inside: avoid;
              page-break-inside: avoid;
            }
            .template-card:first-child {
              margin-top: 0;
            }
            .template-card__title {
              font-size: 18px;
              font-weight: 700;
              line-height: 1.4;
            }
            .template-card__title--tinted {
              padding: 10px 14px;
            }
            .template-card__title--plain {
              padding: 16px 16px 0;
            }
            .template-card__body {
              padding: 14px 16px 16px;
            }
            .template-card__body--plain-title {
              padding-top: 16px;
            }
            .template-card__body p {
              margin: 0;
              line-height: 1.7;
            }
            .template-card__body p + p {
              margin-top: 12px;
            }
            .template-list {
              margin: 0;
              padding: 0;
              list-style: none;
            }
            .template-list li {
              position: relative;
              padding-left: 18px;
              line-height: 1.7;
              margin-top: 9px;
            }
            .template-list li::before {
              content: "";
              position: absolute;
              left: 0;
              top: 11px;
              width: 7px;
              height: 7px;
              border-radius: 999px;
              background: currentColor;
              opacity: 0.88;
            }
            .template-placeholder {
              font-style: italic;
              opacity: 0.72;
            }
            p, li, blockquote {
              line-height: 1.7;
              color: var(--body);
            }
            ul {
              padding-left: 20px;
            }
            @page {
              size: A4;
              margin: 24px;
            }
            @media print {
              body {
                background: #ffffff;
                padding: 0;
              }
              .document {
                max-width: none;
                margin: 0;
                border: none;
                border-radius: 0;
                padding: 0;
                background: #ffffff;
              }
              h1, h2, h3 {
                break-after: avoid;
                page-break-after: avoid;
              }
            }
            @media (max-width: 720px) {
              body { padding: 16px; }
              .document { padding: 20px; }
              h1 { font-size: 28px; }
            }
          </style>
        </head>
        <body>
          <main class="document">
            <div class="header-row">
              <span class="meta-pill">\(templateName)</span>
              <span class="meta-text">\(languageLabel)</span>
              <span class="meta-text">\(visualTemplate)</span>
            </div>
            <h1>\(title)</h1>
            <div class="markdown-body">
              \(bodyHTML)
            </div>
          </main>
        </body>
        </html>
        """
    }

    private func plainPreview(for draft: DraftVersion) -> String {
        MarkdownPlainTextRenderer.render(blocks: renderedBlocks(for: draft, surface: .export))
    }

    private func documentXML(for draft: DraftVersion) -> String {
        var paragraphs: [String] = []
        let title = draft.structuredDoc.title
        paragraphs.append(wordParagraph(title, style: .title))
        paragraphs.append(
            wordParagraph(
                "\(draft.structuredDoc.exportMetadata.contentTemplateName) · \(draft.structuredDoc.outputLanguageLabel(for: draft.outputLanguage)) · \(draft.structuredDoc.exportMetadata.visualTemplateName)",
                style: .meta
            )
        )
        let blocks = renderedBlocks(for: draft, surface: .export)
        for block in blocks {
            switch block.kind {
            case .heading1:
                if block.text != title {
                    paragraphs.append(wordParagraph(block.text, style: .title))
                }
            case .heading2:
                paragraphs.append(wordParagraph(block.text, style: .heading))
            case .heading3:
                paragraphs.append(wordParagraph(block.text, style: .subheading))
            case .paragraph, .quote:
                paragraphs.append(wordParagraph(block.text, style: .body))
            case .list:
                for item in block.items {
                    paragraphs.append(wordParagraph("• \(item)", style: .bullet))
                }
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs.joined())
          </w:body>
        </w:document>
        """
    }

    private func wordParagraph(_ text: String, style: WordParagraphStyle) -> String {
        let escaped = escapedXML(text)
        let properties: String
        switch style {
        case .title:
            properties = """
            <w:pPr><w:spacing w:after="220"/></w:pPr>
            <w:rPr><w:b/><w:color w:val="165FCA"/><w:sz w:val="34"/></w:rPr>
            """
        case .meta:
            properties = """
            <w:pPr><w:spacing w:after="180"/></w:pPr>
            <w:rPr><w:color w:val="667085"/><w:sz w:val="20"/></w:rPr>
            """
        case .heading:
            properties = """
            <w:pPr><w:spacing w:before="180" w:after="100"/></w:pPr>
            <w:rPr><w:b/><w:color w:val="165FCA"/><w:sz w:val="26"/></w:rPr>
            """
        case .subheading:
            properties = """
            <w:pPr><w:spacing w:before="120" w:after="60"/></w:pPr>
            <w:rPr><w:b/><w:color w:val="2A3347"/><w:sz w:val="22"/></w:rPr>
            """
        case .body:
            properties = """
            <w:pPr><w:spacing w:after="90"/></w:pPr>
            <w:rPr><w:sz w:val="22"/></w:rPr>
            """
        case .bullet:
            properties = """
            <w:pPr><w:spacing w:after="60"/></w:pPr>
            <w:rPr><w:sz w:val="22"/></w:rPr>
            """
        }

        return """
        <w:p>
          \(properties)
          <w:r><w:t xml:space="preserve">\(escaped)</w:t></w:r>
        </w:p>
        """
    }

    private func sectionLabel(_ section: ExportSectionLabel, language: OutputLanguage) -> String {
        switch (section, language) {
        case (.summary, .chinese): return "摘要"
        case (.cueQuestions, .chinese): return "复习提示"
        case (.keyPoints, .chinese): return "重点"
        case (.callouts, .chinese): return "提示框"
        case (.glossary, .chinese): return "术语"
        case (.studyCards, .chinese): return "学习问答"
        case (.reviewQuestions, .chinese): return "自测问题"
        case (.actionItems, .chinese): return "行动项"
        case (.suggestedFigures, .chinese): return "建议插图"
        case (.summary, .english): return "Summary"
        case (.cueQuestions, .english): return "Cue Questions"
        case (.keyPoints, .english): return "Key Points"
        case (.callouts, .english): return "Callouts"
        case (.glossary, .english): return "Glossary"
        case (.studyCards, .english): return "Study Cards"
        case (.reviewQuestions, .english): return "Review Questions"
        case (.actionItems, .english): return "Action Items"
        case (.suggestedFigures, .english): return "Suggested Figures"
        }
    }

    private func fileStem(for draft: DraftVersion) -> String {
        draft.structuredDoc.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func renderedMarkdown(for draft: DraftVersion, surface: RenderSurface) -> String {
        (try? draft.renderedMarkdown(for: surface)) ?? sourceMarkdown(for: draft)
    }

    private func renderedBlocks(for draft: DraftVersion, surface: RenderSurface) -> [MarkdownBlock] {
        (try? MarkdownDocument.parse(renderedMarkdown(for: draft, surface: surface)).blocks) ?? [
            MarkdownBlock(kind: .paragraph, text: renderedMarkdown(for: draft, surface: surface), items: [])
        ]
    }

    private func sourceMarkdown(for draft: DraftVersion) -> String {
        draft.editorDocument.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func documentTheme(for draft: DraftVersion) -> DocumentTheme {
        guard let pack = try? draft.resolvedTemplatePackForRendering() else {
            return DocumentTheme.named(draft.structuredDoc.exportMetadata.visualTemplateName)
        }

        return DocumentTheme(
            name: draft.structuredDoc.exportMetadata.visualTemplateName,
            accentHex: pack.style.accentHex,
            accentSoftHex: pack.style.surfaceHex,
            surfaceHex: pack.style.surfaceHex,
            borderHex: pack.style.borderHex,
            secondaryHex: pack.style.secondaryHex
        )
    }

    private func escapedXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapedHTML(_ value: String) -> String {
        escapedXML(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func paragraphHTML(_ value: String) -> String {
        escapedHTML(value)
            .replacingOccurrences(of: "\n\n", with: "</p><p>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func renderedTemplateBodyHTML(
        _ renderedTemplate: RenderedTemplateDocument,
        pack: TemplatePack,
        theme: DocumentTheme
    ) -> String {
        renderedTemplate.blocks.map { block in
            let boxStyle = resolvedBoxStyle(for: block, in: pack)

            if block.blockType == .section {
                return """
                <section class="template-section">
                  <h2>\(escapedHTML(block.title))</h2>
                  \(templateCardHTML(block: block, style: boxStyle, theme: theme, title: nil))
                </section>
                """
            }

            return templateCardHTML(block: block, style: boxStyle, theme: theme, title: block.title)
        }.joined(separator: "\n")
    }

    private func templateCardHTML(
        block: RenderedTemplateBlock,
        style: TemplateBoxStyle,
        theme: DocumentTheme,
        title: String?
    ) -> String {
        let titleColor = style.titleTextHex
        let bodyColor = style.bodyTextHex
        let background = style.backgroundHex
        let border = style.borderHex
        let titleBackground = style.titleBackgroundHex ?? ""
        let codeStyle = TemplateBlockStyleVariant(rawValue: block.styleVariant) == .code
        let hasTitle = !(title?.isEmpty ?? true)

        let titleHTML: String
        if let title, !title.isEmpty {
            if let titleBackgroundHex = style.titleBackgroundHex {
                titleHTML = """
                <div class="template-card__title template-card__title--tinted" style="background:\(escapedHTML(titleBackgroundHex)); color:\(escapedHTML(titleColor));">\(escapedHTML(title))</div>
                """
            } else {
                titleHTML = """
                <div class="template-card__title template-card__title--plain" style="color:\(escapedHTML(titleColor));">\(escapedHTML(title))</div>
                """
            }
        } else {
            titleHTML = ""
        }

        let bodyClass = !hasTitle ? "template-card__body" : (titleBackground.isEmpty ? "template-card__body template-card__body--plain-title" : "template-card__body")
        let bodyFontStyle = codeStyle ? "font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;" : ""
        let bodyHTML = (block.body?.isEmpty == false)
            ? "<p style=\"color:\(escapedHTML(bodyColor)); \(bodyFontStyle)\">\(paragraphHTML(block.body ?? ""))</p>"
            : ""
        let itemsHTML = block.items.isEmpty ? "" : """
        <ul class="template-list" style="color:\(escapedHTML(bodyColor)); \(bodyFontStyle)">
          \(block.items.map { "<li>\(escapedHTML($0))</li>" }.joined())
        </ul>
        """
        let placeholderHTML = (block.placeholderText?.isEmpty == false)
            ? "<p class=\"template-placeholder\" style=\"color:\(escapedHTML(bodyColor));\">\(escapedHTML(block.placeholderText ?? ""))</p>"
            : ""

        return """
        <section class="template-card" style="background:\(escapedHTML(background)); border-color:\(escapedHTML(border));">
          \(titleHTML)
          <div class="\(bodyClass)">
            \(bodyHTML)
            \(itemsHTML)
            \(placeholderHTML)
          </div>
        </section>
        """
    }

    private func resolvedBoxStyle(for block: RenderedTemplateBlock, in pack: TemplatePack) -> TemplateBoxStyle {
        let fallback: TemplateBlockStyleVariant = switch block.blockType {
        case .summary:
            .summary
        case .keyPoints:
            .key
        case .warningBox:
            .warning
        case .studyCards, .reviewQuestions, .exercise:
            .exam
        case .actionItems:
            .result
        case .title, .section, .cueQuestions, .callouts, .glossary:
            .standard
        }
        let resolvedVariant = TemplateBlockStyleVariant(rawValue: block.styleVariant) ?? fallback
        return pack.style.boxStyles.first(where: { $0.variant == resolvedVariant })
            ?? pack.style.boxStyles.first(where: { $0.variant == .standard })
            ?? TemplateBoxStyle(
                variant: resolvedVariant,
                borderHex: pack.style.borderHex,
                backgroundHex: "#FFFFFF",
                titleBackgroundHex: nil,
                titleTextHex: pack.style.accentHex,
                bodyTextHex: "#22304A"
            )
    }

    private func withAlphaHex(_ hex: String, alpha: Double) -> String? {
        guard let color = NSColor(hex: hex) else { return nil }
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return "rgba(\(Int(rgb.redComponent * 255)), \(Int(rgb.greenComponent * 255)), \(Int(rgb.blueComponent * 255)), \(String(format: "%.3f", alpha)))"
    }
}

private enum DocumentExportLayout {
    static let pageSize = NSSize(width: 794, height: 1123)
    static let pagePadding: CGFloat = 24
}

private struct TemplatePackPDFRenderer {
    let renderedDocument: RenderedTemplateDocument
    let pack: TemplatePack
    let contentTemplateName: String
    let outputLanguageLabel: String
    let visualTemplateName: String
    let pageSize: NSSize

    private let pagePadding: CGFloat = 24
    private let blockSpacing: CGFloat = 18
    private let headerSpacing: CGFloat = 20
    private let sectionSpacing: CGFloat = 10
    private let cardCornerRadius: CGFloat = 20

    private var contentWidth: CGFloat {
        pageSize.width - (pagePadding * 2)
    }

    private var accent: NSColor {
        NSColor(hex: pack.style.accentHex) ?? .controlAccentColor
    }

    private var accentSoft: NSColor {
        NSColor(hex: pack.style.surfaceHex) ?? accent.withAlphaComponent(0.1)
    }

    private var surface: NSColor {
        NSColor(hex: pack.style.surfaceHex) ?? .white
    }

    private var border: NSColor {
        NSColor(hex: pack.style.borderHex) ?? accent.withAlphaComponent(0.14)
    }

    private var secondary: NSColor {
        NSColor(hex: pack.style.secondaryHex) ?? .secondaryLabelColor
    }

    func write(to url: URL) throws {
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: pageSize.height))
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfCreationFailed
        }

        var cursorY = pagePadding
        var isFirstPage = true

        func beginPage() {
            context.beginPDFPage(nil as CFDictionary?)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)
            context.saveGState()
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        }

        func endPage() {
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }

        func resetCursorForPageHeader() {
            cursorY = pagePadding
            if isFirstPage {
                cursorY += drawHeader(at: cursorY)
                cursorY += headerSpacing
            }
        }

        beginPage()
        resetCursorForPageHeader()

        for block in renderedDocument.blocks {
            let boxStyle = resolvedBoxStyle(for: block)
            let blockHeight = measuredBlockHeight(for: block, style: boxStyle)
            if cursorY + blockHeight > pageSize.height - pagePadding, cursorY > pagePadding {
                endPage()
                isFirstPage = false
                beginPage()
                resetCursorForPageHeader()
            }

            drawBlock(block, style: boxStyle, at: CGPoint(x: pagePadding, y: cursorY))
            cursorY += blockHeight + blockSpacing
        }

        endPage()
        context.closePDF()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExportError.pdfCreationFailed
        }
    }

    private func drawHeader(at y: CGFloat) -> CGFloat {
        let rowHeight: CGFloat = 22
        let pillPaddingX: CGFloat = 10
        let pillPaddingY: CGFloat = 6
        let pillFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let metaFont = NSFont.systemFont(ofSize: 12, weight: .regular)

        let pillSize = measuredTextSize(contentTemplateName, font: pillFont, width: contentWidth)
        let pillWidth = pillSize.width + (pillPaddingX * 2)
        let pillRect = CGRect(x: pagePadding, y: y, width: pillWidth, height: max(rowHeight, pillSize.height + (pillPaddingY * 2)))
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 999, yRadius: 999)
        accentSoft.setFill()
        pillPath.fill()
        drawText(
            contentTemplateName,
            in: pillRect.insetBy(dx: pillPaddingX, dy: pillPaddingY),
            font: pillFont,
            color: accent
        )

        let languageWidth = measuredTextSize(outputLanguageLabel, font: metaFont, width: 220).width
        let languageRect = CGRect(x: pillRect.maxX + 12, y: y + 4, width: languageWidth, height: 18)
        drawText(outputLanguageLabel, in: languageRect, font: metaFont, color: secondary)

        let visualWidth = measuredTextSize(visualTemplateName, font: metaFont, width: 220).width
        let visualRect = CGRect(x: pagePadding + contentWidth - visualWidth, y: y + 4, width: visualWidth, height: 18)
        drawText(visualTemplateName, in: visualRect, font: metaFont, color: secondary, alignment: .right)

        return max(pillRect.height, rowHeight)
    }

    private func measuredBlockHeight(for block: RenderedTemplateBlock, style: TemplateBoxStyle) -> CGFloat {
        let cardHeight = measuredCardHeight(for: block, style: style)
        if block.blockType == .section {
            let headingHeight = measuredTextHeight(
                block.title,
                font: NSFont.systemFont(ofSize: 24, weight: .bold),
                width: contentWidth
            )
            return headingHeight + sectionSpacing + cardHeight
        }
        return cardHeight
    }

    private func measuredCardHeight(for block: RenderedTemplateBlock, style: TemplateBoxStyle) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
        let bodyFont = bodyFont(for: block)
        let bodyWidth = contentWidth - 32
        var total: CGFloat = 0

        if block.blockType != .section, !block.title.isEmpty {
            let titleWidth = style.titleBackgroundHex == nil ? contentWidth - 32 : contentWidth - 28
            let titleHeight = measuredTextHeight(block.title, font: titleFont, width: titleWidth)
            total += titleHeight + (style.titleBackgroundHex == nil ? 16 : 20)
        }

        let bodyPadding = (style.titleBackgroundHex == nil && block.blockType != .section && !block.title.isEmpty) ? CGFloat(16) : CGFloat(14)
        var contentHeight: CGFloat = 0
        var contentSections = 0

        if let body = block.body, !body.isEmpty {
            contentHeight += measuredParagraphHeight(body, font: bodyFont, width: bodyWidth)
            contentSections += 1
        }

        if !block.items.isEmpty {
            contentHeight += measuredListHeight(block.items, font: bodyFont, width: bodyWidth - 18)
            contentSections += 1
        }

        if let placeholder = block.placeholderText, !placeholder.isEmpty {
            contentHeight += measuredParagraphHeight(placeholder, font: bodyFont, width: bodyWidth)
            contentSections += 1
        }

        if contentSections > 1 {
            contentHeight += CGFloat(contentSections - 1) * 12
        }

        total += contentHeight + (bodyPadding * 2)
        return max(total, 56)
    }

    private func drawBlock(_ block: RenderedTemplateBlock, style: TemplateBoxStyle, at origin: CGPoint) {
        var cardOriginY = origin.y
        if block.blockType == .section {
            let headingHeight = measuredTextHeight(
                block.title,
                font: NSFont.systemFont(ofSize: 24, weight: .bold),
                width: contentWidth
            )
            drawText(
                block.title,
                in: CGRect(x: origin.x, y: origin.y, width: contentWidth, height: headingHeight),
                font: NSFont.systemFont(ofSize: 24, weight: .bold),
                color: accent
            )
            cardOriginY += headingHeight + sectionSpacing
        }

        let cardHeight = measuredCardHeight(for: block, style: style)
        let cardRect = CGRect(x: origin.x, y: cardOriginY, width: contentWidth, height: cardHeight)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cardCornerRadius, yRadius: cardCornerRadius)
        (NSColor(hex: style.backgroundHex) ?? surface).setFill()
        cardPath.fill()
        (NSColor(hex: style.borderHex) ?? border).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        let titleColor = NSColor(hex: style.titleTextHex) ?? accent
        let bodyColor = NSColor(hex: style.bodyTextHex) ?? .labelColor
        let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
        let bodyFont = bodyFont(for: block)
        var bodyTopY = cardRect.minY

        if block.blockType != .section, !block.title.isEmpty {
            if let titleBackgroundHex = style.titleBackgroundHex,
               let titleBackground = NSColor(hex: titleBackgroundHex) {
                let titleHeight = measuredTextHeight(block.title, font: titleFont, width: contentWidth - 28) + 20
                NSGraphicsContext.saveGraphicsState()
                cardPath.addClip()
                titleBackground.setFill()
                NSBezierPath(rect: CGRect(x: cardRect.minX, y: cardRect.minY, width: cardRect.width, height: titleHeight)).fill()
                NSGraphicsContext.restoreGraphicsState()
                drawText(
                    block.title,
                    in: CGRect(x: cardRect.minX + 14, y: cardRect.minY + 10, width: cardRect.width - 28, height: titleHeight - 20),
                    font: titleFont,
                    color: titleColor
                )
                bodyTopY = cardRect.minY + titleHeight
            } else {
                let titleHeight = measuredTextHeight(block.title, font: titleFont, width: contentWidth - 32)
                drawText(
                    block.title,
                    in: CGRect(x: cardRect.minX + 16, y: cardRect.minY + 16, width: cardRect.width - 32, height: titleHeight),
                    font: titleFont,
                    color: titleColor
                )
                bodyTopY = cardRect.minY + 16 + titleHeight
            }
        }

        let bodyPadding = (style.titleBackgroundHex == nil && block.blockType != .section && !block.title.isEmpty) ? CGFloat(16) : CGFloat(14)
        var cursorY = bodyTopY + bodyPadding
        let bodyX = cardRect.minX + 16
        let bodyWidth = cardRect.width - 32

        if let body = block.body, !body.isEmpty {
            let paragraphHeight = measuredParagraphHeight(body, font: bodyFont, width: bodyWidth)
            drawParagraph(body, in: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: paragraphHeight), font: bodyFont, color: bodyColor)
            cursorY += paragraphHeight
        }

        if !block.items.isEmpty {
            if cursorY > bodyTopY + bodyPadding {
                cursorY += 12
            }
            cursorY += drawList(block.items, color: titleColor.withAlphaComponent(bodyFont.fontName.contains("Mono") ? 0.45 : 0.88), textColor: bodyColor, font: bodyFont, at: CGPoint(x: bodyX, y: cursorY), width: bodyWidth)
        }

        if let placeholder = block.placeholderText, !placeholder.isEmpty {
            if cursorY > bodyTopY + bodyPadding {
                cursorY += 12
            }
            let paragraphHeight = measuredParagraphHeight(placeholder, font: bodyFont, width: bodyWidth)
            drawParagraph(placeholder, in: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: paragraphHeight), font: bodyFont, color: bodyColor.withAlphaComponent(0.72), italic: true)
        }
    }

    private func drawList(
        _ items: [String],
        color: NSColor,
        textColor: NSColor,
        font: NSFont,
        at origin: CGPoint,
        width: CGFloat
    ) -> CGFloat {
        var cursorY = origin.y
        for item in items {
            let itemHeight = measuredParagraphHeight(item, font: font, width: width - 18)
            let bulletRect = CGRect(x: origin.x, y: cursorY + 7, width: 7, height: 7)
            let bulletPath = NSBezierPath(ovalIn: bulletRect)
            color.setFill()
            bulletPath.fill()
            drawParagraph(item, in: CGRect(x: origin.x + 18, y: cursorY, width: width - 18, height: itemHeight), font: font, color: textColor)
            cursorY += itemHeight + 9
        }
        return max(0, cursorY - origin.y - 9)
    }

    private func drawParagraph(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        italic: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        let resolvedFont = italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: resolvedFont,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    private func measuredParagraphHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )
        return ceil(attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    private func measuredTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        ceil(measuredTextSize(text, font: font, width: width).height)
    }

    private func measuredTextSize(_ text: String, font: NSFont, width: CGFloat) -> CGSize {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        return attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).integral.size
    }

    private func measuredListHeight(_ items: [String], font: NSFont, width: CGFloat) -> CGFloat {
        items.enumerated().reduce(CGFloat(0)) { partial, element in
            let itemHeight = measuredParagraphHeight(element.element, font: font, width: width)
            return partial + itemHeight + (element.offset == items.count - 1 ? 0 : 9)
        }
    }

    private func bodyFont(for block: RenderedTemplateBlock) -> NSFont {
        if TemplateBlockStyleVariant(rawValue: block.styleVariant) == .code {
            return NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        }
        return NSFont.systemFont(ofSize: 16, weight: .regular)
    }

    private func resolvedBoxStyle(for block: RenderedTemplateBlock) -> TemplateBoxStyle {
        let fallback: TemplateBlockStyleVariant = switch block.blockType {
        case .summary:
            .summary
        case .keyPoints:
            .key
        case .warningBox:
            .warning
        case .studyCards, .reviewQuestions, .exercise:
            .exam
        case .actionItems:
            .result
        case .title, .section, .cueQuestions, .callouts, .glossary:
            .standard
        }

        let resolvedVariant = TemplateBlockStyleVariant(rawValue: block.styleVariant) ?? fallback
        return pack.style.boxStyles.first(where: { $0.variant == resolvedVariant })
            ?? pack.style.boxStyles.first(where: { $0.variant == .standard })
            ?? TemplateBoxStyle(
                variant: resolvedVariant,
                borderHex: pack.style.borderHex,
                backgroundHex: "#FFFFFF",
                titleBackgroundHex: nil,
                titleTextHex: pack.style.accentHex,
                bodyTextHex: "#22304A"
            )
    }
}

private enum WordParagraphStyle {
    case title
    case meta
    case heading
    case subheading
    case body
    case bullet
}

private enum ExportSectionLabel {
    case summary
    case cueQuestions
    case keyPoints
    case callouts
    case glossary
    case studyCards
    case reviewQuestions
    case actionItems
    case suggestedFigures
}

private extension StructuredDocument {
    func outputLanguageLabel(for language: OutputLanguage) -> String {
        language == .chinese ? "中文 Output" : "English Output"
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

private let contentTypesXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
"""

private let relsXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""
