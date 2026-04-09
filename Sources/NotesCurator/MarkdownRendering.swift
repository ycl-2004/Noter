import Foundation

enum MarkdownBlockKind: Equatable {
    case heading1
    case heading2
    case heading3
    case paragraph
    case list
    case quote
}

struct MarkdownBlock: Equatable {
    let kind: MarkdownBlockKind
    let text: String
    let items: [String]
}

enum MarkdownRenderingError: Error, Equatable {
    case invalidBlock(String)
}

struct MarkdownDocument: Equatable {
    let blocks: [MarkdownBlock]

    static func parse(_ source: String) throws -> MarkdownDocument {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                index += 1
                continue
            }

            if line.hasPrefix("# ") {
                blocks.append(MarkdownBlock(kind: .heading1, text: String(line.dropFirst(2)).trimmed, items: []))
                index += 1
                continue
            }

            if line.hasPrefix("## ") {
                blocks.append(MarkdownBlock(kind: .heading2, text: String(line.dropFirst(3)).trimmed, items: []))
                index += 1
                continue
            }

            if line.hasPrefix("### ") {
                blocks.append(MarkdownBlock(kind: .heading3, text: String(line.dropFirst(4)).trimmed, items: []))
                index += 1
                continue
            }

            if line.hasPrefix("> ") {
                var quoteLines: [String] = [String(line.dropFirst(2)).trimmed]
                index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix("> ") else { break }
                    quoteLines.append(String(next.dropFirst(2)).trimmed)
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .quote, text: quoteLines.joined(separator: "\n"), items: []))
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var items: [String] = []
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix("- ") || next.hasPrefix("* ") else { break }
                    items.append(String(next.dropFirst(2)).trimmed)
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .list, text: "", items: items))
                continue
            }

            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("#") || next.hasPrefix("- ") || next.hasPrefix("* ") || next.hasPrefix("> ") {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }
            blocks.append(MarkdownBlock(kind: .paragraph, text: paragraphLines.joined(separator: "\n"), items: []))
        }

        return MarkdownDocument(blocks: blocks)
    }
}

enum MarkdownHTMLRenderer {
    static func render(
        _ source: String,
        theme: DocumentTheme = .named("Oceanic Blue")
    ) throws -> String {
        try render(
            blocks: MarkdownDocument.parse(source).blocks,
            theme: theme
        )
    }

    static func render(
        blocks: [MarkdownBlock],
        theme: DocumentTheme = .named("Oceanic Blue")
    ) throws -> String {
        blocks.map { block in
            switch block.kind {
            case .heading1:
                return "<h1>\(escapedHTML(block.text))</h1>"
            case .heading2:
                return "<h2>\(escapedHTML(block.text))</h2>"
            case .heading3:
                return "<h3>\(escapedHTML(block.text))</h3>"
            case .paragraph:
                return "<p>\(inlineHTML(block.text))</p>"
            case .list:
                let items = block.items.map { "<li>\(inlineHTML($0))</li>" }.joined()
                return "<ul>\(items)</ul>"
            case .quote:
                return "<blockquote>\(block.text.split(separator: "\n").map { "<p>\(inlineHTML(String($0)))</p>" }.joined())</blockquote>"
            }
        }
        .joined(separator: "\n")
    }

    private static func inlineHTML(_ text: String) -> String {
        let escaped = escapedHTML(text)
        return escaped
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: #"(?s)\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
    }

    private static func escapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum MarkdownPlainTextRenderer {
    static func render(_ source: String) -> String {
        guard let document = try? MarkdownDocument.parse(source) else {
            return source.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return render(blocks: document.blocks)
    }

    static func render(blocks: [MarkdownBlock]) -> String {
        blocks.map { block in
            switch block.kind {
            case .heading1, .heading2, .heading3:
                return block.text
            case .paragraph, .quote:
                return block.text
            case .list:
                return block.items.map { "• \($0)" }.joined(separator: "\n")
            }
        }
        .joined(separator: "\n\n")
        .replacingOccurrences(of: #"(?m)\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: #"(?m)\*(.+?)\*"#, with: "$1", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
