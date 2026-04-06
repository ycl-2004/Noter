import AppKit
import Foundation
import PDFKit
import Testing
@testable import NotesCurator

struct ParsingTests {
    @Test
    func localParserReadsPlainTextMarkdownDocxAndPDF() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let txtURL = workspace.appendingPathComponent("notes.txt")
        try "Quarterly budget needs review.".write(to: txtURL, atomically: true, encoding: .utf8)

        let mdURL = workspace.appendingPathComponent("notes.md")
        try "# Branding\nNeed a calmer blue system.".write(to: mdURL, atomically: true, encoding: .utf8)

        let docxURL = workspace.appendingPathComponent("meeting.docx")
        try createDOCX(at: docxURL, body: "Project Phoenix needs a formal summary.")

        let pdfURL = workspace.appendingPathComponent("report.pdf")
        try createPDF(at: pdfURL, text: "Revenue grew 24 percent year over year.")

        let parser = LocalIntakeParser()
        let parsed = try await parser.parse(
            IntakeRequest(
                pastedText: "Pasted source",
                fileURLs: [txtURL, mdURL, docxURL, pdfURL],
                goalType: .summary,
                outputLanguage: .english,
                contentTemplateName: "Summary",
                visualTemplateName: "Oceanic Blue"
            )
        )

        #expect(parsed.text.contains("Pasted source"))
        #expect(parsed.text.contains("Quarterly budget needs review."))
        #expect(parsed.text.contains("Need a calmer blue system."))
        #expect(parsed.text.contains("Project Phoenix needs a formal summary."))
        #expect(parsed.text.contains("Revenue grew 24 percent year over year."))
        #expect(parsed.sources.count == 5)
    }

    @Test
    func ocrServiceRecognizesRenderedText() async throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let size = NSSize(width: 1_200, height: 320)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let text = "Budget 15% Tuesday"
        text.draw(
            at: NSPoint(x: 60, y: 110),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let pngData = representation.representation(using: .png, properties: [:]) else {
            Issue.record("Unable to generate PNG data for OCR validation.")
            return
        }
        try pngData.write(to: imageURL)

        let recognized = try await OCRService.shared.recognizeText(at: imageURL)
        #expect(recognized.localizedCaseInsensitiveContains("Budget"))
        #expect(recognized.contains("15"))
    }
}

private func createDOCX(at url: URL, body: String) throws {
    let fileManager = FileManager.default
    let working = url.deletingPathExtension().appendingPathExtension("build")
    try fileManager.createDirectory(at: working.appendingPathComponent("_rels"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: working.appendingPathComponent("word"), withIntermediateDirectories: true)

    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """.write(to: working.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """.write(to: working.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)

    try """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:body><w:p><w:r><w:t>\(body)</w:t></w:r></w:p></w:body>
    </w:document>
    """.write(to: working.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = working
    process.arguments = ["-q", "-r", url.path, "."]
    try process.run()
    process.waitUntilExit()
    try? fileManager.removeItem(at: working)
}

private func createPDF(at url: URL, text: String) throws {
    let pdf = PDFDocument()
    let image = NSImage(size: NSSize(width: 500, height: 700))
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 500, height: 700)).fill()
    NSString(string: text).draw(
        in: NSRect(x: 32, y: 320, width: 420, height: 100),
        withAttributes: [.font: NSFont.systemFont(ofSize: 18)]
    )
    image.unlockFocus()
    pdf.insert(PDFPage(image: image)!, at: 0)
    pdf.write(to: url)
}
