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
        let hostingView = makePDFHostingView(for: draft)
        let printInfo = NSPrintInfo()
        printInfo.paperSize = DocumentExportLayout.pageSize
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let operation = NSPrintOperation.pdfOperation(
            with: hostingView,
            inside: hostingView.bounds,
            toPath: url.path,
            printInfo: printInfo
        )
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false

        guard operation.run() else {
            throw ExportError.pdfCreationFailed
        }
        return url
    }

    private func makePDFHostingView(for draft: DraftVersion) -> NSHostingView<some View> {
        let rootView = ZStack(alignment: .topLeading) {
            Color.white
            StyledDraftPreview(version: draft)
                .padding(DocumentExportLayout.pagePadding)
        }
        .frame(width: DocumentExportLayout.pageSize.width)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.setFrameSize(NSSize(width: DocumentExportLayout.pageSize.width, height: 1))
        hostingView.layoutSubtreeIfNeeded()

        let fittingHeight = max(DocumentExportLayout.pageSize.height, ceil(hostingView.fittingSize.height))
        hostingView.setFrameSize(NSSize(width: DocumentExportLayout.pageSize.width, height: fittingHeight))
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
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
        let blocks = renderedBlocks(for: draft, surface: .export)
        let bodyHTML = (try? MarkdownHTMLRenderer.render(blocks: blocks, theme: theme))
            ?? "<p>\(paragraphHTML(renderedMarkdown(for: draft, surface: .export)))</p>"

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
            p, li, blockquote {
              line-height: 1.7;
              color: var(--body);
            }
            ul {
              padding-left: 20px;
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
