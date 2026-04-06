import AppKit
import Foundation
import PDFKit
@preconcurrency import Vision

struct LocalIntakeParser: IntakeParser {
    func parse(_ request: IntakeRequest) async throws -> ParsedDocument {
        var textSegments: [String] = []
        var sources: [SourceReference] = []
        var images: [ParsedImageAsset] = []

        if !request.pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textSegments.append(request.pastedText)
            sources.append(
                SourceReference(
                    kind: .pastedText,
                    title: "Pasted Text",
                    excerpt: String(request.pastedText.prefix(140))
                )
            )
        }

        for fileURL in request.fileURLs {
            let parsedFile = try await parseFile(at: fileURL)
            if !parsedFile.text.isEmpty {
                textSegments.append(parsedFile.text)
            }
            sources.append(parsedFile.source)
            images.append(contentsOf: parsedFile.images)
        }

        return ParsedDocument(
            text: textSegments.joined(separator: "\n\n"),
            sources: sources,
            images: images
        )
    }

    private func parseFile(at url: URL) async throws -> ParsedFile {
        switch url.pathExtension.lowercased() {
        case "txt":
            let text = try String(contentsOf: url, encoding: .utf8)
            return ParsedFile(text: text, source: source(for: .txtFile, url: url, excerpt: text), images: [])
        case "md":
            let text = try String(contentsOf: url, encoding: .utf8)
            return ParsedFile(text: text, source: source(for: .markdownFile, url: url, excerpt: text), images: [])
        case "docx":
            return try await parseDOCX(at: url)
        case "pdf":
            return try await parsePDF(at: url)
        default:
            let text = try String(contentsOf: url, encoding: .utf8)
            return ParsedFile(text: text, source: source(for: .txtFile, url: url, excerpt: text), images: [])
        }
    }

    private func parseDOCX(at url: URL) async throws -> ParsedFile {
        let documentXML = try unzipText(path: url.path, member: "word/document.xml")
        let text = XMLWordTextExtractor.extractText(from: documentXML)

        let mediaList = try unzipList(path: url.path).filter { $0.hasPrefix("word/media/") }
        let images = try await mediaList.asyncMap { entry in
            let tempImage = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension((entry as NSString).pathExtension)
            defer { try? FileManager.default.removeItem(at: tempImage) }

            try unzipFile(path: url.path, member: entry, outputURL: tempImage)
            let ocrText = try await OCRService.shared.recognizeText(at: tempImage)
            return ParsedImageAsset(
                title: tempImage.deletingPathExtension().lastPathComponent,
                summary: ocrText.isEmpty ? "Imported image from DOCX" : "Image with extracted text",
                ocrText: ocrText
            )
        }

        return ParsedFile(
            text: text,
            source: source(for: .docxFile, url: url, excerpt: text),
            images: images
        )
    }

    private func parsePDF(at url: URL) async throws -> ParsedFile {
        guard let document = PDFDocument(url: url) else {
            return ParsedFile(text: "", source: source(for: .pdfFile, url: url, excerpt: ""), images: [])
        }

        var allText: [String] = []
        var images: [ParsedImageAsset] = []

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !pageText.isEmpty {
                allText.append(pageText)
            } else {
                let pageImage = page.thumbnail(of: NSSize(width: 1_024, height: 1_024), for: .mediaBox)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
                try save(image: pageImage, to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                let ocrText = try await OCRService.shared.recognizeText(at: tempURL)
                if !ocrText.isEmpty {
                    allText.append(ocrText)
                    images.append(
                        ParsedImageAsset(
                            title: "Page \(index + 1)",
                            summary: "Scanned PDF page with extracted text",
                            ocrText: ocrText
                        )
                    )
                }
            }
        }

        let merged = allText.joined(separator: "\n\n")
        return ParsedFile(
            text: merged,
            source: source(for: .pdfFile, url: url, excerpt: merged),
            images: images
        )
    }

    private func source(for kind: SourceKind, url: URL, excerpt: String) -> SourceReference {
        SourceReference(kind: kind, title: url.lastPathComponent, excerpt: String(excerpt.prefix(140)))
    }

    private func unzipText(path: String, member: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", path, member]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func unzipList(path: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    private func unzipFile(path: String, member: String, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", path, member]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try data.write(to: outputURL)
    }

    private func save(image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try png.write(to: url)
    }
}

private struct ParsedFile {
    var text: String
    var source: SourceReference
    var images: [ParsedImageAsset]
}

enum XMLWordTextExtractor {
    static func extractText(from xml: String) -> String {
        let pattern = "<w:t[^>]*>(.*?)</w:t>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return xml }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, range: nsRange)
        let chunks = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            return String(xml[range])
        }
        return chunks.joined(separator: "\n")
    }
}

actor OCRService {
    static let shared = OCRService()

    func recognizeText(at imageURL: URL) async throws -> String {
        guard let image = NSImage(contentsOf: imageURL),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest { request, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        let text = (request.results as? [VNRecognizedTextObservation])?
                            .compactMap { $0.topCandidates(1).first?.string }
                            .joined(separator: "\n") ?? ""
                        continuation.resume(returning: text)
                    }
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

                    let handler = VNImageRequestHandler(cgImage: cgImage)
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension Array {
    fileprivate func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async throws -> [T] {
        var output: [T] = []
        for element in self {
            output.append(try await transform(element))
        }
        return output
    }
}
