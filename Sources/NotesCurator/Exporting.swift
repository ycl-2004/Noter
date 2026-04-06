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
        let document = draft.structuredDoc
        var lines = [
            "# \(document.title)",
            "",
            "_\(document.exportMetadata.contentTemplateName) · \(document.outputLanguageLabel(for: draft.outputLanguage)) · \(document.exportMetadata.visualTemplateName)_",
            "",
            "## \(sectionLabel(.summary, language: draft.outputLanguage))",
            document.summary,
            "",
        ]

        appendBulletSection(
            title: sectionLabel(.cueQuestions, language: draft.outputLanguage),
            items: document.cueQuestions,
            to: &lines
        )
        appendBulletSection(title: sectionLabel(.keyPoints, language: draft.outputLanguage), items: document.keyPoints, to: &lines)

        if !document.callouts.isEmpty {
            lines.append("## \(sectionLabel(.callouts, language: draft.outputLanguage))")
            lines.append("")
            for callout in document.callouts {
                lines.append("> **\(calloutBadge(for: callout.kind)) \(callout.title)**")
                lines.append("> \(callout.body)")
                lines.append("")
            }
        }

        for section in document.sections {
            lines.append("## \(section.title)")
            lines.append(section.body)
            if !section.bulletPoints.isEmpty {
                lines.append("")
                lines.append(contentsOf: section.bulletPoints.map { "- \($0)" })
            }
            lines.append("")
        }

        if !document.glossary.isEmpty {
            lines.append("## \(sectionLabel(.glossary, language: draft.outputLanguage))")
            lines.append("")
            lines.append(contentsOf: document.glossary.map { "- **\($0.term)**: \($0.definition)" })
            lines.append("")
        }

        appendStudyCardSection(
            title: sectionLabel(.studyCards, language: draft.outputLanguage),
            cards: document.studyCards,
            language: draft.outputLanguage,
            to: &lines
        )
        appendBulletSection(title: sectionLabel(.reviewQuestions, language: draft.outputLanguage), items: document.reviewQuestions, to: &lines)
        appendBulletSection(title: sectionLabel(.actionItems, language: draft.outputLanguage), items: document.actionItems, to: &lines)

        if !document.imageSlots.isEmpty {
            lines.append("## \(sectionLabel(.suggestedFigures, language: draft.outputLanguage))")
            lines.append("")
            lines.append(contentsOf: document.imageSlots.map { "- \($0.caption)" })
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func htmlDocument(for draft: DraftVersion) -> String {
        let document = draft.structuredDoc
        let theme = DocumentTheme.named(document.exportMetadata.visualTemplateName)
        let title = escapedHTML(document.title)
        let summary = paragraphHTML(document.summary)
        let templateName = escapedHTML(document.exportMetadata.contentTemplateName.uppercased())
        let languageLabel = escapedHTML(document.outputLanguageLabel(for: draft.outputLanguage))
        let visualTemplate = escapedHTML(document.exportMetadata.visualTemplateName)

        var sections: [String] = []

        if !document.cueQuestions.isEmpty {
            sections.append(htmlListSection(
                title: sectionLabel(.cueQuestions, language: draft.outputLanguage),
                items: document.cueQuestions,
                tone: theme.accentSoftHex
            ))
        }

        if !document.keyPoints.isEmpty {
            sections.append(htmlListSection(
                title: sectionLabel(.keyPoints, language: draft.outputLanguage),
                items: document.keyPoints,
                tone: withAlphaHex(theme.accentHex, alpha: 0.08) ?? theme.accentSoftHex
            ))
        }

        if !document.callouts.isEmpty {
            let callouts = document.callouts.map { callout in
                """
                <article class="callout \(callout.kind.rawValue)">
                  <div class="eyebrow">\(escapedHTML(calloutBadge(for: callout.kind)))</div>
                  <h3>\(escapedHTML(callout.title))</h3>
                  <p>\(paragraphHTML(callout.body))</p>
                </article>
                """
            }.joined()

            sections.append("""
            <section class="stack">
              <h2 class="section-heading">\(escapedHTML(sectionLabel(.callouts, language: draft.outputLanguage)))</h2>
              <div class="callouts">\(callouts)</div>
            </section>
            """)
        }

        let bodySections = document.sections.enumerated().map { index, section in
            let bullets = section.bulletPoints.isEmpty ? "" : """
            <ul class="bullet-list">
              \(section.bulletPoints.map { "<li>\(paragraphHTML($0))</li>" }.joined())
            </ul>
            """

            return """
            <article class="content-card">
              <div class="section-title-row">
                <span class="section-number">\(index + 1)</span>
                <h2>\(escapedHTML(section.title))</h2>
              </div>
              <p>\(paragraphHTML(section.body))</p>
              \(bullets)
            </article>
            """
        }.joined()
        sections.append(bodySections)

        if !document.glossary.isEmpty {
            let glossary = document.glossary.map { item in
                """
                <article class="glossary-card">
                  <h3>\(escapedHTML(item.term))</h3>
                  <p>\(paragraphHTML(item.definition))</p>
                </article>
                """
            }.joined()
            sections.append("""
            <section class="stack">
              <h2 class="section-heading">\(escapedHTML(sectionLabel(.glossary, language: draft.outputLanguage)))</h2>
              <div class="glossary-grid">\(glossary)</div>
            </section>
            """)
        }

        if !document.studyCards.isEmpty {
            let cards = document.studyCards.map { card in
                """
                <article class="content-card compact">
                  <h3>\(escapedHTML(card.question))</h3>
                  <p>\(paragraphHTML(card.answer))</p>
                </article>
                """
            }.joined()
            sections.append("""
            <section class="stack">
              <h2 class="section-heading">\(escapedHTML(sectionLabel(.studyCards, language: draft.outputLanguage)))</h2>
              <div class="stack-gap">\(cards)</div>
            </section>
            """)
        }

        if !document.reviewQuestions.isEmpty {
            sections.append(htmlListSection(
                title: sectionLabel(.reviewQuestions, language: draft.outputLanguage),
                items: document.reviewQuestions,
                tone: withAlphaHex(theme.accentHex, alpha: 0.08) ?? theme.accentSoftHex
            ))
        }

        if !document.actionItems.isEmpty {
            sections.append(htmlListSection(
                title: sectionLabel(.actionItems, language: draft.outputLanguage),
                items: document.actionItems,
                tone: theme.accentSoftHex
            ))
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
            h2.section-heading {
              margin: 0 0 10px;
              color: var(--accent);
              font-size: 13px;
              letter-spacing: 0.08em;
              text-transform: uppercase;
            }
            .summary-card, .content-card, .glossary-card, .callout {
              background: var(--canvas);
              border: 1px solid color-mix(in srgb, var(--accent) 12%, white);
              border-radius: 20px;
              padding: 18px;
            }
            .content-card {
              padding: 20px;
              border-radius: 22px;
            }
            .content-card.compact {
              padding: 16px;
              border-radius: 18px;
            }
            .stack {
              margin-top: 22px;
            }
            .stack-gap > * + * { margin-top: 12px; }
            .list-card {
              padding: 16px;
              border-radius: 18px;
            }
            .list-card ul, .bullet-list {
              margin: 0;
              padding-left: 20px;
            }
            .list-card li, .bullet-list li {
              margin: 8px 0;
            }
            .callouts, .glossary-grid {
              display: grid;
              gap: 12px;
            }
            .glossary-grid {
              grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
            }
            .callout.warning { background: var(--warning); border-color: #f0dcc6; }
            .callout.example { background: var(--example); border-color: #d9eddc; }
            .callout.keyIdea { background: color-mix(in srgb, var(--accent) 8%, white); }
            .eyebrow {
              color: var(--accent);
              font-size: 12px;
              font-weight: 700;
              margin-bottom: 6px;
            }
            .section-number {
              width: 22px;
              height: 22px;
              display: inline-flex;
              align-items: center;
              justify-content: center;
              border-radius: 999px;
              color: var(--accent);
              background: var(--accent-soft);
              font-size: 12px;
              font-weight: 700;
            }
            p, li {
              line-height: 1.7;
              color: var(--body);
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
            <section class="summary-card">
              <p>\(summary)</p>
            </section>
            \(sections.joined(separator: "\n"))
          </main>
        </body>
        </html>
        """
    }

    private func htmlListSection(title: String, items: [String], tone: String) -> String {
        """
        <section class="stack">
          <h2 class="section-heading">\(escapedHTML(title))</h2>
          <div class="list-card" style="background: \(tone);">
            <ul>
              \(items.map { "<li>\(paragraphHTML($0))</li>" }.joined())
            </ul>
          </div>
        </section>
        """
    }

    private func appendBulletSection(title: String, items: [String], to lines: inout [String]) {
        guard !items.isEmpty else { return }
        lines.append("## \(title)")
        lines.append("")
        lines.append(contentsOf: items.map { "- \($0)" })
        lines.append("")
    }

    private func plainPreview(for draft: DraftVersion) -> String {
        let document = draft.structuredDoc
        var chunks = [document.title, "", document.summary]

        if !document.keyPoints.isEmpty {
            chunks.append("")
            chunks.append(sectionLabel(.keyPoints, language: draft.outputLanguage))
            chunks.append(document.keyPoints.map { "• \($0)" }.joined(separator: "\n"))
        }

        for section in document.sections {
            chunks.append("")
            chunks.append(section.title)
            chunks.append(section.body)
            if !section.bulletPoints.isEmpty {
                chunks.append(section.bulletPoints.map { "• \($0)" }.joined(separator: "\n"))
            }
        }

        if !document.actionItems.isEmpty {
            chunks.append("")
            chunks.append(sectionLabel(.actionItems, language: draft.outputLanguage))
            chunks.append(document.actionItems.map { "• \($0)" }.joined(separator: "\n"))
        }

        if !document.studyCards.isEmpty {
            chunks.append("")
            chunks.append(sectionLabel(.studyCards, language: draft.outputLanguage))
            chunks.append(
                document.studyCards.map { card in
                    "• \(studyCardQuestionPrefix(for: draft.outputLanguage)) \(card.question)\n  \(studyCardAnswerPrefix(for: draft.outputLanguage)) \(card.answer)"
                }.joined(separator: "\n")
            )
        }

        return chunks.joined(separator: "\n")
    }

    private func documentXML(for draft: DraftVersion) -> String {
        let document = draft.structuredDoc
        var paragraphs: [String] = []
        paragraphs.append(wordParagraph(document.title, style: .title))
        paragraphs.append(
            wordParagraph(
                "\(document.exportMetadata.contentTemplateName) · \(document.outputLanguageLabel(for: draft.outputLanguage)) · \(document.exportMetadata.visualTemplateName)",
                style: .meta
            )
        )
        paragraphs.append(wordParagraph(sectionLabel(.summary, language: draft.outputLanguage), style: .heading))
        paragraphs.append(wordParagraph(document.summary, style: .body))

        appendWordSection(title: sectionLabel(.cueQuestions, language: draft.outputLanguage), items: document.cueQuestions, to: &paragraphs)
        appendWordSection(title: sectionLabel(.keyPoints, language: draft.outputLanguage), items: document.keyPoints, to: &paragraphs)

        if !document.callouts.isEmpty {
            paragraphs.append(wordParagraph(sectionLabel(.callouts, language: draft.outputLanguage), style: .heading))
            for callout in document.callouts {
                paragraphs.append(wordParagraph("\(calloutBadge(for: callout.kind)) \(callout.title)", style: .subheading))
                paragraphs.append(wordParagraph(callout.body, style: .body))
            }
        }

        for section in document.sections {
            paragraphs.append(wordParagraph(section.title, style: .heading))
            paragraphs.append(wordParagraph(section.body, style: .body))
            for bullet in section.bulletPoints {
                paragraphs.append(wordParagraph("• \(bullet)", style: .bullet))
            }
        }

        if !document.glossary.isEmpty {
            paragraphs.append(wordParagraph(sectionLabel(.glossary, language: draft.outputLanguage), style: .heading))
            for entry in document.glossary {
                paragraphs.append(wordParagraph("\(entry.term): \(entry.definition)", style: .body))
            }
        }

        appendStudyCardWordSection(
            title: sectionLabel(.studyCards, language: draft.outputLanguage),
            cards: document.studyCards,
            language: draft.outputLanguage,
            to: &paragraphs
        )
        appendWordSection(title: sectionLabel(.reviewQuestions, language: draft.outputLanguage), items: document.reviewQuestions, to: &paragraphs)
        appendWordSection(title: sectionLabel(.actionItems, language: draft.outputLanguage), items: document.actionItems, to: &paragraphs)

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs.joined())
          </w:body>
        </w:document>
        """
    }

    private func appendWordSection(title: String, items: [String], to paragraphs: inout [String]) {
        guard !items.isEmpty else { return }
        paragraphs.append(wordParagraph(title, style: .heading))
        for item in items {
            paragraphs.append(wordParagraph("• \(item)", style: .bullet))
        }
    }

    private func appendStudyCardWordSection(
        title: String,
        cards: [StudyCard],
        language: OutputLanguage,
        to paragraphs: inout [String]
    ) {
        guard !cards.isEmpty else { return }
        paragraphs.append(wordParagraph(title, style: .heading))
        for card in cards {
            paragraphs.append(
                wordParagraph(
                    "• \(studyCardQuestionPrefix(for: language)) \(card.question)\n\(studyCardAnswerPrefix(for: language)) \(card.answer)",
                    style: .bullet
                )
            )
        }
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

    private func calloutBadge(for kind: StructuredCalloutKind) -> String {
        switch kind {
        case .keyIdea: return "KEY IDEA"
        case .note: return "NOTE"
        case .warning: return "WATCH OUT"
        case .example: return "EXAMPLE"
        }
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

    private func appendStudyCardSection(
        title: String,
        cards: [StudyCard],
        language: OutputLanguage,
        to lines: inout [String]
    ) {
        guard !cards.isEmpty else { return }
        lines.append("## \(title)")
        lines.append("")
        lines.append(contentsOf: cards.map {
            "- \(studyCardQuestionPrefix(for: language)) \($0.question)\n  \(studyCardAnswerPrefix(for: language)) \($0.answer)"
        })
        lines.append("")
    }

    private func studyCardQuestionPrefix(for language: OutputLanguage) -> String {
        language == .chinese ? "问：" : "Q:"
    }

    private func studyCardAnswerPrefix(for language: OutputLanguage) -> String {
        language == .chinese ? "答：" : "A:"
    }

    private func fileStem(for draft: DraftVersion) -> String {
        draft.structuredDoc.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
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
