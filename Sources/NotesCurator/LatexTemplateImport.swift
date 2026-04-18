import Foundation

enum LatexTemplateImportError: Error, Equatable, LocalizedError {
    case unsupportedSource(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSource(message):
            return message
        }
    }
}

struct SourceFingerprint: Equatable, Sendable {
    var palette: SourcePalette
    var boxStyles: [LatexBoxStyle]
    var headingSystem: LatexHeadingSystem
    var recurringSections: [String]
    var geometry: LatexGeometryHints
}

struct SourcePalette: Equatable, Sendable {
    var accentHex: String
    var surfaceHex: String?
    var namedColors: [String: String]
}

struct LatexBoxStyle: Equatable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var frameColorName: String?
    var backgroundColorName: String?
    var title: String?
}

enum LatexHeadingSystem: Equatable, Sendable {
    case academicStructured
    case simpleDocument
}

struct LatexGeometryHints: Equatable, Sendable {
    var margin: String?
    var spacingHints: [String]

    init(
        margin: String? = nil,
        spacingHints: [String] = []
    ) {
        self.margin = margin
        self.spacingHints = spacingHints
    }
}

enum LatexTemplateImporter {
    static func extractFingerprint(from source: String) throws -> SourceFingerprint {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let palette = try extractPalette(from: normalized)

        return SourceFingerprint(
            palette: palette,
            boxStyles: extractBoxStyles(from: normalized),
            headingSystem: extractHeadingSystem(from: normalized),
            recurringSections: extractSections(from: normalized),
            geometry: extractGeometryHints(from: normalized)
        )
    }

    static func importTemplate(from source: String) throws -> TemplateImportReview {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let fingerprint = try extractFingerprint(from: normalized)
        let archetype = inferArchetype(from: fingerprint, source: normalized)
        let preview = buildImportedPreview(
            from: normalized,
            fallbackTitle: suggestedTemplateName(from: normalized, archetype: archetype)
        )
        var templatePack = TemplatePackDefaults.importedPack(
            archetype: archetype,
            fingerprint: fingerprint,
            suggestedName: suggestedTemplateName(
                from: normalized,
                archetype: archetype,
                previewTitle: preview.title
            )
        )
        templatePack.style.boxStyles = importedBoxStyles(
            from: normalized,
            fingerprint: fingerprint,
            fallbackStyle: templatePack.style
        )
        templatePack.importedPreview = preview

        return TemplateImportReview(
            source: normalized,
            fingerprint: fingerprint,
            inferredArchetype: archetype,
            templatePack: templatePack,
            latexProjectSource: nil
        )
    }

    private static func extractPalette(from source: String) throws -> SourcePalette {
        let colorPairs = matches(
            pattern: #"\\definecolor\{([^}]+)\}\{HTML\}\{([0-9A-Fa-f]{6})\}"#,
            in: source
        )
        let namedColors = Dictionary(uniqueKeysWithValues: colorPairs.map {
            ($0[0], "#\($0[1].uppercased())")
        })

        guard !namedColors.isEmpty else {
            throw LatexTemplateImportError.unsupportedSource(
                "No supported \\definecolor{...}{HTML}{...} declarations were found."
            )
        }

        let accentHex = namedColors.first {
            let name = $0.key.lowercased()
            return name.contains("accent") || name.contains("primary") || name.contains("brand")
        }?.value ?? namedColors.values.sorted().first!

        let surfaceHex = namedColors.first {
            let name = $0.key.lowercased()
            return name.contains("surface") || name.contains("background") || name.contains("paper")
        }?.value

        return SourcePalette(
            accentHex: accentHex,
            surfaceHex: surfaceHex,
            namedColors: namedColors
        )
    }

    private static func extractBoxStyles(from source: String) -> [LatexBoxStyle] {
        let marker = #"\newtcolorbox{"#
        var styles: [LatexBoxStyle] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            guard let nameEnd = source[markerRange.upperBound...].firstIndex(of: "}") else {
                break
            }

            let name = String(source[markerRange.upperBound..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            var cursor = source.index(after: nameEnd)
            while cursor < source.endIndex, source[cursor].isWhitespace {
                cursor = source.index(after: cursor)
            }

            if cursor < source.endIndex, source[cursor] == "[" {
                guard let parameterEnd = source[cursor...].firstIndex(of: "]") else {
                    break
                }
                cursor = source.index(after: parameterEnd)
                while cursor < source.endIndex, source[cursor].isWhitespace {
                    cursor = source.index(after: cursor)
                }
            }

            guard cursor < source.endIndex, source[cursor] == "{",
                  let (options, optionsEnd) = balancedContent(in: source, startingAt: cursor) else {
                searchStart = markerRange.upperBound
                continue
            }

            styles.append(
                LatexBoxStyle(
                    name: name,
                    frameColorName: optionValue(named: "colframe", in: options),
                    backgroundColorName: optionValue(named: "colback", in: options),
                    title: optionValue(named: "title", in: options)
                )
            )
            searchStart = optionsEnd
        }

        return styles
    }

    private static func extractHeadingSystem(from source: String) -> LatexHeadingSystem {
        let hasStructuredTitleFormatting =
            source.contains(#"\titleformat{\section}"#) &&
            source.contains(#"\titleformat{\subsection}"#)
        let hasStructuredSections =
            source.contains(#"\section{"#) &&
            source.contains(#"\subsection{"#)

        return (hasStructuredTitleFormatting || hasStructuredSections) ? .academicStructured : .simpleDocument
    }

    private static func extractSections(from source: String) -> [String] {
        matches(
            pattern: #"\\section\{([^}]+)\}"#,
            in: source
        )
        .map { $0[0] }
    }

    private static func extractGeometryHints(from source: String) -> LatexGeometryHints {
        let margin = matches(
            pattern: #"\\usepackage\[([^]]*margin\s*=\s*[^,\]]+)[^]]*\]\{geometry\}"#,
            in: source
        )
        .first?[0]

        let spacingHints = matches(
            pattern: #"\\setlength\{([^}]+)\}\{([^}]+)\}"#,
            in: source
        )
        .map { "\($0[0])=\($0[1])" }

        return LatexGeometryHints(
            margin: margin,
            spacingHints: spacingHints
        )
    }

    private static func inferArchetype(from fingerprint: SourceFingerprint, source: String) -> TemplateArchetype {
        let normalized = source.lowercased()
        if fingerprint.recurringSections.contains(where: { $0.lowercased().contains("q&a") }) ||
            fingerprint.boxStyles.contains(where: { $0.name.lowercased().contains("warning") }) {
            return .technicalNote
        }
        if normalized.contains("meeting") || normalized.contains("agenda") {
            return .meetingBrief
        }
        if normalized.contains("memo") || normalized.contains("recommendation") || normalized.contains("brief") {
            return .formalBrief
        }
        return .technicalNote
    }

    private static func suggestedTemplateName(
        from source: String,
        archetype: TemplateArchetype,
        previewTitle: String? = nil
    ) -> String {
        if let title = matches(pattern: #"\\title\{([^}]+)\}"#, in: source).first?[0], !title.isEmpty {
            return title
        }
        if let previewTitle = previewTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !previewTitle.isEmpty {
            return previewTitle
        }

        switch archetype {
        case .technicalNote:
            return "Imported Technical Template"
        case .meetingBrief:
            return "Imported Meeting Template"
        case .formalBrief:
            return "Imported Formal Template"
        }
    }

    private static func optionValue(named name: String, in options: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        return matches(
            pattern: "(?:^|,)\\s*\(escapedName)\\s*=\\s*([^,]+)",
            in: options
        )
        .first?[0]
    }

    private static func matches(pattern: String, in source: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, options: [], range: range).compactMap { result in
            guard result.numberOfRanges > 1 else { return nil }
            return (1..<result.numberOfRanges).compactMap { index in
                guard let range = Range(result.range(at: index), in: source) else {
                    return nil
                }
                return String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private static func balancedContent(
        in source: String,
        startingAt openingBrace: String.Index
    ) -> (content: String, endIndex: String.Index)? {
        guard openingBrace < source.endIndex, source[openingBrace] == "{" else { return nil }

        var depth = 0
        var cursor = openingBrace

        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let contentStart = source.index(after: openingBrace)
                    let content = String(source[contentStart..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (content, source.index(after: cursor))
                }
            }

            cursor = source.index(after: cursor)
        }

        return nil
    }

    private static func importedBoxStyles(
        from source: String,
        fingerprint: SourceFingerprint,
        fallbackStyle: StyleKit
    ) -> [TemplateBoxStyle] {
        var resolved = Dictionary(uniqueKeysWithValues: fallbackStyle.boxStyles.map { ($0.variant, $0) })
        let defaults = defaultTColorBoxOptions(from: source)

        for box in fingerprint.boxStyles {
            let variant = boxVariant(for: box)
            let border = resolveColorExpression(
                box.frameColorName ?? defaults.frameColorName,
                palette: fingerprint.palette
            ) ?? resolved[variant]?.borderHex ?? fallbackStyle.borderHex
            let background = resolveColorExpression(
                box.backgroundColorName ?? defaults.backgroundColorName,
                palette: fingerprint.palette
            ) ?? resolved[variant]?.backgroundHex ?? fallbackStyle.surfaceHex

            let titleBackground: String? = switch variant {
            case .standard:
                nil
            case .summary:
                blend(border, with: "#FFFFFF", firstColorWeight: 0.28)
            case .exam, .code:
                blend(border, with: "#FFFFFF", firstColorWeight: 0.14)
            case .key, .warning, .result:
                border
            }

            let titleText = titleBackground.map(contrastingTextHex(for:)) ?? fallbackStyle.accentHex
            let bodyText = bodyTextHex(for: variant)
            resolved[variant] = TemplateBoxStyle(
                variant: variant,
                borderHex: border,
                backgroundHex: background,
                titleBackgroundHex: titleBackground,
                titleTextHex: titleText,
                bodyTextHex: bodyText
            )
        }

        return TemplateBlockStyleVariant.allCases.compactMap { variant in
            resolved[variant]
        }
    }

    private static func defaultTColorBoxOptions(from source: String) -> (frameColorName: String?, backgroundColorName: String?) {
        let options = matches(
            pattern: #"\\tcbset\{([\s\S]*?)\}"#,
            in: source
        )
        .first?[0] ?? ""

        return (
            optionValue(named: "colframe", in: options),
            optionValue(named: "colback", in: options)
        )
    }

    private static func boxVariant(for style: LatexBoxStyle) -> TemplateBlockStyleVariant {
        let combined = "\(style.name) \(style.title ?? "")".lowercased()
        if combined.contains("warning") { return .warning }
        if combined.contains("result") { return .result }
        if combined.contains("code") { return .code }
        if combined.contains("exam") || combined.contains("exercise") { return .exam }
        if combined.contains("key") { return .key }
        if combined.contains("summary") { return .summary }
        return .summary
    }

    private static func buildImportedPreview(from source: String, fallbackTitle: String) -> ImportedTemplatePreview {
        let document = extractDocumentBody(from: source)
        let lines = document.components(separatedBy: .newlines)
        var title = fallbackTitle
        var subtitle: String?
        var blocks: [ImportedTemplatePreviewBlock] = []
        var index = 0

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty || line.hasPrefix("%") || line == #"\begin{document}"# || line == #"\end{document}"# {
                index += 1
                continue
            }

            if let header = headerText(in: line, command: "Huge") {
                title = sanitizePreviewText(header, preserveLineBreaks: false)
                index += 1
                continue
            }

            if let deckSubtitle = headerText(in: line, command: "large") {
                subtitle = sanitizePreviewText(deckSubtitle, preserveLineBreaks: false)
                index += 1
                continue
            }

            if line.hasPrefix(#"\hrule"#) {
                blocks.append(ImportedTemplatePreviewBlock(kind: .separator))
                index += 1
                continue
            }

            if let heading = extractCommandArgument("section", from: line) {
                blocks.append(
                    ImportedTemplatePreviewBlock(
                        kind: .heading,
                        title: sanitizePreviewText(heading, preserveLineBreaks: false),
                        level: 1
                    )
                )
                index += 1
                continue
            }

            if let heading = extractCommandArgument("subsection", from: line) {
                blocks.append(
                    ImportedTemplatePreviewBlock(
                        kind: .heading,
                        title: sanitizePreviewText(heading, preserveLineBreaks: false),
                        level: 2
                    )
                )
                index += 1
                continue
            }

            if let heading = extractCommandArgument("subsubsection", from: line) {
                blocks.append(
                    ImportedTemplatePreviewBlock(
                        kind: .heading,
                        title: sanitizePreviewText(heading, preserveLineBreaks: false),
                        level: 3
                    )
                )
                index += 1
                continue
            }

            if let (environmentName, environmentTitle) = extractBoxStart(from: line) {
                var bodyLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate.hasPrefix("\\end{\(environmentName)}") {
                        break
                    }
                    bodyLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }

                let parsed = parsePreviewBoxBody(bodyLines, environmentName: environmentName)
                blocks.append(
                    ImportedTemplatePreviewBlock(
                        kind: .box,
                        title: sanitizePreviewText(environmentTitle, preserveLineBreaks: false),
                        body: parsed.body,
                        items: parsed.items,
                        styleVariant: boxVariantName(forEnvironmentName: environmentName),
                        level: 0
                    )
                )
                continue
            }

            if line.hasPrefix(#"\vspace"#) {
                index += 1
                continue
            }

            var paragraphLines: [String] = [rawLine]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if next.isEmpty || next.hasPrefix("%") || isStructuralLine(next) {
                    break
                }
                paragraphLines.append(lines[index])
                index += 1
            }

            let paragraph = sanitizePreviewText(paragraphLines.joined(separator: "\n"), preserveLineBreaks: true)
            if !paragraph.isEmpty {
                blocks.append(
                    ImportedTemplatePreviewBlock(
                        kind: .paragraph,
                        body: paragraph
                    )
                )
            }
        }

        return ImportedTemplatePreview(
            title: title,
            subtitle: subtitle,
            blocks: blocks
        )
    }

    private static func extractDocumentBody(from source: String) -> String {
        guard let startRange = source.range(of: #"\begin{document}"#),
              let endRange = source.range(of: #"\end{document}"#) else {
            return source
        }
        return String(source[startRange.upperBound..<endRange.lowerBound])
    }

    private static func isStructuralLine(_ line: String) -> Bool {
        line.hasPrefix("{\\Huge") ||
            line.hasPrefix("{\\large") ||
            line.hasPrefix(#"\hrule"#) ||
            line.hasPrefix(#"\section{"#) ||
            line.hasPrefix(#"\subsection{"#) ||
            line.hasPrefix(#"\subsubsection{"#) ||
            line.hasPrefix(#"\begin{"#)
    }

    private static func headerText(in line: String, command: String) -> String? {
        let prefix = "{\\\(command)"
        guard line.hasPrefix(prefix),
              let start = line.firstIndex(of: "{"),
              let end = line.lastIndex(of: "}") else {
            return nil
        }
        return String(line[line.index(after: start)..<end])
    }

    private static func extractCommandArgument(_ command: String, from line: String) -> String? {
        matches(
            pattern: #"\\#(command)\{([^}]+)\}"#,
            in: line
        )
        .first?[0]
    }

    private static func extractBoxStart(from line: String) -> (String, String)? {
        guard let match = matches(
            pattern: #"\\begin\{([A-Za-z]+Box)\}\{([^}]*)\}"#,
            in: line
        )
        .first else {
            return nil
        }
        return (match[0], match[1])
    }

    private static func parsePreviewBoxBody(
        _ lines: [String],
        environmentName: String
    ) -> (body: String, items: [String]) {
        let joined = lines.joined(separator: "\n")
        if environmentName.lowercased().contains("code"),
           let code = extractInlineCommand(named: "code", from: joined) {
            return (
                sanitizePreviewText(code, preserveLineBreaks: true),
                []
            )
        }

        var items: [String] = []
        var paragraphLines: [String] = []
        var insideItemize = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("%") {
                continue
            }
            if line.hasPrefix(#"\begin{itemize}"#) {
                insideItemize = true
                continue
            }
            if line.hasPrefix(#"\end{itemize}"#) {
                insideItemize = false
                continue
            }
            if insideItemize, line.hasPrefix(#"\item"#) {
                let item = line.replacingOccurrences(of: #"\item"#, with: "")
                let cleaned = sanitizePreviewText(item, preserveLineBreaks: true)
                if !cleaned.isEmpty {
                    items.append(cleaned)
                }
                continue
            }

            paragraphLines.append(rawLine)
        }

        return (
            sanitizePreviewText(paragraphLines.joined(separator: "\n"), preserveLineBreaks: true),
            items
        )
    }

    private static func extractInlineCommand(named name: String, from source: String) -> String? {
        matches(
            pattern: #"\\#(name)\{([\s\S]*?)\}"#,
            in: source
        )
        .first?[0]
    }

    private static func boxVariantName(forEnvironmentName name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("warning") { return TemplateBlockStyleVariant.warning.rawValue }
        if lowered.contains("result") { return TemplateBlockStyleVariant.result.rawValue }
        if lowered.contains("code") { return TemplateBlockStyleVariant.code.rawValue }
        if lowered.contains("exam") || lowered.contains("exercise") { return TemplateBlockStyleVariant.exam.rawValue }
        if lowered.contains("key") { return TemplateBlockStyleVariant.key.rawValue }
        return TemplateBlockStyleVariant.summary.rawValue
    }

    private static func sanitizePreviewText(_ source: String, preserveLineBreaks: Bool) -> String {
        var text = source
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: #"\\"#, with: preserveLineBreaks ? "\n" : " ")
        text = text.replacingOccurrences(of: #"\&"#, with: "&")
        text = text.replacingOccurrences(of: #"\%"#, with: "%")
        text = text.replacingOccurrences(of: #"\_"#, with: "_")
        text = text.replacingOccurrences(of: #"\\textbf\{([\s\S]*?)\}"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\texttt\{([\s\S]*?)\}"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\code\{([\s\S]*?)\}"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\color\{[^}]+\}"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\\[A-Za-z]+\*?(?:\[[^\]]*\])?"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "{", with: "")
        text = text.replacingOccurrences(of: "}", with: "")
        if preserveLineBreaks {
            text = text.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        } else {
            text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveColorExpression(_ expression: String?, palette: SourcePalette) -> String? {
        guard let expression = expression?.trimmingCharacters(in: .whitespacesAndNewlines), !expression.isEmpty else {
            return nil
        }

        let sanitized = expression.replacingOccurrences(of: " ", with: "")
        if sanitized.hasPrefix("#"), sanitized.count == 7 {
            return sanitized.uppercased()
        }
        if sanitized.range(of: #"^[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil {
            return "#\(sanitized.uppercased())"
        }

        let components = sanitized.components(separatedBy: "!")
        if components.count == 2,
           let first = resolveColorExpression(components[0], palette: palette),
           let percent = Double(components[1]) {
            return blend(first, with: "#FFFFFF", firstColorWeight: percent / 100)
        }
        if components.count == 3,
           let first = resolveColorExpression(components[0], palette: palette),
           let percent = Double(components[1]),
           let second = resolveColorExpression(components[2], palette: palette) {
            return blend(first, with: second, firstColorWeight: percent / 100)
        }

        let key = sanitized.lowercased()
        if let named = palette.namedColors.first(where: { $0.key.lowercased() == key })?.value {
            return named
        }
        return builtinColorHexes[key]
    }

    private static func bodyTextHex(for variant: TemplateBlockStyleVariant) -> String {
        switch variant {
        case .warning:
            return "#4A2A2A"
        case .result:
            return "#1F3D2A"
        case .code:
            return "#1E293B"
        case .standard, .summary, .key, .exam:
            return "#22304A"
        }
    }

    private static func contrastingTextHex(for backgroundHex: String) -> String {
        guard let rgb = rgbComponents(for: backgroundHex) else { return "#FFFFFF" }
        let luminance = (0.299 * rgb.red) + (0.587 * rgb.green) + (0.114 * rgb.blue)
        return luminance > 0.68 ? "#22304A" : "#FFFFFF"
    }

    private static func blend(_ firstHex: String, with secondHex: String, firstColorWeight: Double) -> String? {
        guard let first = rgbComponents(for: firstHex),
              let second = rgbComponents(for: secondHex) else {
            return nil
        }

        let weight = max(0, min(firstColorWeight, 1))
        let inverse = 1 - weight
        let red = (first.red * weight) + (second.red * inverse)
        let green = (first.green * weight) + (second.green * inverse)
        let blue = (first.blue * weight) + (second.blue * inverse)
        return hexString(red: red, green: green, blue: blue)
    }

    private static func rgbComponents(for hex: String) -> (red: Double, green: Double, blue: Double)? {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func hexString(red: Double, green: Double, blue: Double) -> String {
        let r = Int(max(0, min(red, 1)) * 255)
        let g = Int(max(0, min(green, 1)) * 255)
        let b = Int(max(0, min(blue, 1)) * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static let builtinColorHexes: [String: String] = [
        "red": "#E35D5B",
        "green": "#3C8C53",
        "black": "#1F2937",
        "white": "#FFFFFF",
        "blue": "#2563EB",
        "gray": "#94A3B8",
        "grey": "#94A3B8",
    ]
}

extension TemplateImportReview {
    func rebuild(for archetype: TemplateArchetype) -> TemplateImportReview {
        TemplateImportReview(
            source: source,
            fingerprint: fingerprint,
            inferredArchetype: archetype,
            templatePack: TemplatePackDefaults.importedPack(
                archetype: archetype,
                fingerprint: fingerprint,
                suggestedName: templatePack.identity.name
            ),
            latexProjectSource: latexProjectSource
        )
    }
}
