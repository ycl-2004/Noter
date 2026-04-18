import Foundation

enum LatexProjectError: Error, Equatable, LocalizedError {
    case missingMainFile(String)
    case unsupportedProject(String)
    case mainFileIsNotUTF8(String)
    case missingCompilerTool(String)
    case compilationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingMainFile(message),
             let .unsupportedProject(message),
             let .mainFileIsNotUTF8(message),
             let .missingCompilerTool(message),
             let .compilationFailed(message):
            return message
        }
    }
}

enum LatexCompilerProfile: String, Codable, CaseIterable, Equatable, Sendable {
    case xelatex
    case pdflatex
    case latexmkXelatex
    case latexmkPdfLatex

    var toolName: String {
        switch self {
        case .xelatex:
            return "xelatex"
        case .pdflatex:
            return "pdflatex"
        case .latexmkXelatex, .latexmkPdfLatex:
            return "latexmk"
        }
    }

    func arguments(mainFilePath: String) -> [String] {
        switch self {
        case .xelatex, .pdflatex:
            return [
                "-interaction=nonstopmode",
                "-halt-on-error",
                mainFilePath
            ]
        case .latexmkXelatex:
            return [
                "-xelatex",
                "-interaction=nonstopmode",
                "-halt-on-error",
                mainFilePath
            ]
        case .latexmkPdfLatex:
            return [
                "-pdf",
                "-interaction=nonstopmode",
                "-halt-on-error",
                mainFilePath
            ]
        }
    }
}

struct LatexProjectFile: Codable, Equatable, Sendable, Identifiable {
    var id: String { path }
    var path: String
    var data: Data

    static func text(path: String, contents: String) -> LatexProjectFile {
        LatexProjectFile(path: path, data: Data(contents.utf8))
    }

    var textContents: String? {
        String(data: data, encoding: .utf8)
    }
}

enum LatexProjectSlotField: String, Codable, CaseIterable, Equatable, Sendable {
    case title
    case summary
    case keyPoints
    case sections
    case sectionBlocks
    case actionItems
    case reviewQuestions
    case glossary
    case studyCards
    case cueQuestions
    case callouts
    case warnings
    case templateBoxes
    case summaryBoxes
    case keyBoxes
    case metaBoxes
    case warningBoxes
    case codeBoxes
    case resultBoxes
    case examBoxes
    case checklistBoxes
    case questionBoxes
    case explanationBoxes
    case exampleBoxes
}

struct LatexProjectSlotBinding: Codable, Equatable, Sendable {
    var token: String
    var field: LatexProjectSlotField
}

struct LatexProjectSource: Codable, Equatable, Sendable {
    var mainFilePath: String
    var compiler: LatexCompilerProfile
    var files: [LatexProjectFile]
    var slotBindings: [LatexProjectSlotBinding]

    init(
        mainFilePath: String,
        compiler: LatexCompilerProfile,
        files: [LatexProjectFile],
        slotBindings: [LatexProjectSlotBinding]
    ) {
        self.mainFilePath = Self.normalized(path: mainFilePath)
        self.compiler = compiler
        self.files = files.map { file in
            var copy = file
            copy.path = Self.normalized(path: copy.path)
            return copy
        }
        self.slotBindings = slotBindings
    }

    var mainFileText: String? {
        file(at: mainFilePath)?.textContents
    }

    func file(at path: String) -> LatexProjectFile? {
        let normalized = Self.normalized(path: path)
        return files.first(where: { Self.normalized(path: $0.path) == normalized })
    }

    func updatingMainFile(text: String) -> LatexProjectSource {
        var updatedFiles = files
        let normalizedMain = Self.normalized(path: mainFilePath)
        if let index = updatedFiles.firstIndex(where: { Self.normalized(path: $0.path) == normalizedMain }) {
            updatedFiles[index] = .text(path: normalizedMain, contents: text)
        } else {
            updatedFiles.append(.text(path: normalizedMain, contents: text))
        }
        return LatexProjectSource(
            mainFilePath: normalizedMain,
            compiler: compiler,
            files: updatedFiles,
            slotBindings: slotBindings
        )
    }

    func writing(to directory: URL, renderedMainFile: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for file in files {
            let destination = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let payload: Data
            if Self.normalized(path: file.path) == Self.normalized(path: mainFilePath),
               let renderedMainFile {
                payload = Data(renderedMainFile.utf8)
            } else {
                payload = file.data
            }

            try payload.write(to: destination)
        }

        return directory.appendingPathComponent(mainFilePath)
    }

    private static func normalized(path: String) -> String {
        var normalized = path.replacingOccurrences(of: "\\", with: "/")
        while normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }
        return normalized
    }
}

struct LatexCommandResult: Equatable, Sendable {
    var terminationStatus: Int32
    var standardOutput: Data
    var standardError: Data
}

protocol LatexCommandExecuting: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> LatexCommandResult
}

protocol LatexToolLocating: Sendable {
    func toolURL(for compiler: LatexCompilerProfile) -> URL?
}

struct ProcessLatexCommandExecutor: LatexCommandExecuting {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> LatexCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return LatexCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: stdout.fileHandleForReading.readDataToEndOfFile(),
            standardError: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

struct DefaultLatexToolLocator: LatexToolLocating {
    func toolURL(for compiler: LatexCompilerProfile) -> URL? {
        let candidates = [
            "/Library/TeX/texbin/\(compiler.toolName)",
            "/usr/texbin/\(compiler.toolName)",
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(compiler.toolName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

struct LatexProjectCompiler: Sendable {
    var executor: any LatexCommandExecuting
    var locator: any LatexToolLocating

    init(
        executor: any LatexCommandExecuting = ProcessLatexCommandExecutor(),
        locator: any LatexToolLocating = DefaultLatexToolLocator()
    ) {
        self.executor = executor
        self.locator = locator
    }

    func compile(project: LatexProjectSource, in directory: URL) throws -> URL {
        let mainURL = try project.writing(to: directory)
        let source = project.mainFileText ?? ""
        let candidates = compilerCandidates(for: project.compiler, source: source)
        var missingToolNames: [String] = []
        var failures: [String] = []

        for candidate in candidates {
            guard let toolURL = locator.toolURL(for: candidate) else {
                missingToolNames.append(candidate.toolName)
                continue
            }

            let result = try executor.run(
                executableURL: toolURL,
                arguments: candidate.arguments(mainFilePath: mainURL.lastPathComponent),
                currentDirectoryURL: mainURL.deletingLastPathComponent()
            )

            guard result.terminationStatus == 0 else {
                let stderr = String(decoding: result.standardError, as: UTF8.self)
                let stdout = String(decoding: result.standardOutput, as: UTF8.self)
                let message = [stderr, stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty })
                    ?? "LaTeX compilation failed."
                failures.append("\(candidate.toolName): \(message)")
                continue
            }

            let pdfURL = mainURL.deletingPathExtension().appendingPathExtension("pdf")
            guard FileManager.default.fileExists(atPath: pdfURL.path) else {
                failures.append("\(candidate.toolName): Expected compiled PDF at \(pdfURL.lastPathComponent), but it was not created.")
                continue
            }

            return pdfURL
        }

        if failures.isEmpty == false {
            throw LatexProjectError.compilationFailed(failures.joined(separator: "\n\n"))
        }

        let triedTools = Array(NSOrderedSet(array: missingToolNames)).compactMap { $0 as? String }
        throw LatexProjectError.missingCompilerTool(
            "Could not find a working local TeX compiler on this Mac. Tried: \(triedTools.joined(separator: ", ")). Install MacTeX/BasicTeX or point Notes at a machine with xelatex/pdflatex available."
        )
    }

    private func compilerCandidates(for preferred: LatexCompilerProfile, source: String) -> [LatexCompilerProfile] {
        let unicodePreferred: [LatexCompilerProfile] = [
            preferred,
            .xelatex,
            .latexmkXelatex,
            .pdflatex,
            .latexmkPdfLatex,
        ]
        let pdfPreferred: [LatexCompilerProfile] = [
            preferred,
            .pdflatex,
            .latexmkPdfLatex,
            .xelatex,
            .latexmkXelatex,
        ]

        let ordered = sourceRequiresXeLaTeX(source) ? unicodePreferred : pdfPreferred
        var seen: Set<LatexCompilerProfile> = []
        return ordered.filter { seen.insert($0).inserted }
    }

    private func sourceRequiresXeLaTeX(_ source: String) -> Bool {
        if source.contains("\\usepackage[UTF8]{ctex}") ||
            source.contains("\\setCJKmainfont") ||
            source.contains("\\setmainfont") {
            return true
        }

        return source.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF:
                return true
            default:
                return false
            }
        }
    }
}

enum LatexProjectRenderer {
    static func renderMainFile(project: LatexProjectSource, document: StructuredDocument) throws -> String {
        guard var source = project.mainFileText else {
            throw LatexProjectError.mainFileIsNotUTF8("The main TeX file could not be read as UTF-8 text.")
        }

        source = renderOptionalBlocks(in: source, document: document)

        for binding in project.slotBindings {
            source = source.replacingOccurrences(
                of: binding.token,
                with: renderedValue(for: binding.field, document: document)
            )
        }

        return source
    }

    private static func renderOptionalBlocks(in source: String, document: StructuredDocument) -> String {
        let beginPrefix = "% notescurator.optional.begin:"
        let endPrefix = "% notescurator.optional.end:"
        var rendered = source

        while let beginMarkerRange = rendered.range(of: beginPrefix) {
            let beginLineRange = rendered.lineRange(for: beginMarkerRange)
            let fieldName = rendered[beginMarkerRange.upperBound..<beginLineRange.upperBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let endMarker = "\(endPrefix)\(fieldName)"

            guard let endMarkerRange = rendered.range(of: endMarker, range: beginLineRange.upperBound..<rendered.endIndex) else {
                break
            }

            let endLineRange = rendered.lineRange(for: endMarkerRange)
            let innerRange = beginLineRange.upperBound..<endMarkerRange.lowerBound
            let inner = String(rendered[innerRange])

            let replacement: String
            if let field = LatexProjectSlotField(rawValue: fieldName),
               renderedValue(for: field, document: document).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                replacement = inner.trimmingCharacters(in: .newlines)
            } else {
                replacement = ""
            }

            rendered.replaceSubrange(beginLineRange.lowerBound..<endLineRange.upperBound, with: replacement)
        }

        return rendered
    }

    private static func renderedValue(for field: LatexProjectSlotField, document: StructuredDocument) -> String {
        switch field {
        case .title:
            return latexEscaped(document.title)
        case .summary:
            return latexParagraphs(document.summary)
        case .keyPoints:
            return latexItemList(document.keyPoints)
        case .sections:
            return document.sections.map { renderedSection($0, command: "subsection*") }.joined(separator: "\n\n")
        case .sectionBlocks:
            return document.sections.map { renderedSection($0, command: "section") }.joined(separator: "\n\n")
        case .actionItems:
            return latexItemList(document.actionItems)
        case .reviewQuestions:
            return latexItemList(document.reviewQuestions)
        case .glossary:
            return document.glossary
                .map { "\\textbf{\(latexEscaped($0.term))}: \(latexEscaped($0.definition))" }
                .joined(separator: "\n\n")
        case .studyCards:
            return document.studyCards
                .map { "\\textbf{Q:} \(latexEscaped($0.question))\n\n\\textbf{A:} \(latexEscaped($0.answer))" }
                .joined(separator: "\n\n")
        case .cueQuestions:
            return latexItemList(document.cueQuestions)
        case .callouts:
            return renderedCallouts(document.callouts.filter { $0.kind != .warning })
        case .warnings:
            return renderedCallouts(document.callouts.filter { $0.kind == .warning })
        case .templateBoxes:
            return document.templateBoxes
                .map { box in
                    let body = latexParagraphs(box.body)
                    let items = latexItemList(box.items)
                    return [latexEscaped(box.title), body, items]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n\n")
                }
                .joined(separator: "\n\n")
        case .summaryBoxes:
            return renderedTemplateBoxContent(for: .summary, document: document)
        case .keyBoxes:
            return renderedTemplateBoxContent(for: .key, document: document)
        case .metaBoxes:
            return renderedTemplateBoxContent(for: .meta, document: document)
        case .warningBoxes:
            return renderedTemplateBoxContent(for: .warning, document: document)
        case .codeBoxes:
            return renderedTemplateBoxContent(for: .code, document: document)
        case .resultBoxes:
            return renderedTemplateBoxContent(for: .result, document: document)
        case .examBoxes:
            return renderedTemplateBoxContent(for: .exam, document: document)
        case .checklistBoxes:
            return renderedTemplateBoxContent(for: .checklist, document: document)
        case .questionBoxes:
            return renderedTemplateBoxContent(for: .question, document: document)
        case .explanationBoxes:
            return renderedTemplateBoxContent(for: .explanation, document: document)
        case .exampleBoxes:
            return renderedTemplateBoxContent(for: .example, document: document)
        }
    }

    private static func renderedSection(_ section: StructuredSection, command: String) -> String {
        var chunks = [
            "\\\(command){\(latexEscaped(section.title))}",
            latexParagraphs(section.body)
        ]
        if !section.bulletPoints.isEmpty {
            chunks.append(latexItemList(section.bulletPoints))
        }
        return chunks.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func renderedCallouts(_ callouts: [StructuredCallout]) -> String {
        callouts
            .map { callout in
                let title = callout.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = callout.body.trimmingCharacters(in: .whitespacesAndNewlines)

                var chunks: [String] = []
                if !title.isEmpty {
                    chunks.append("\\textbf{\(latexEscaped(title))}")
                }
                if !body.isEmpty {
                    chunks.append(latexParagraphs(body))
                }
                return chunks.joined(separator: "\n\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func renderedTemplateBoxContent(
        for kind: StructuredTemplateBoxKind,
        document: StructuredDocument
    ) -> String {
        templateBoxes(for: kind, document: document)
            .map { box in
                let title = box.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = box.body.trimmingCharacters(in: .whitespacesAndNewlines)

                var chunks: [String] = []
                if !title.isEmpty {
                    chunks.append("\\textbf{\(latexEscaped(title))}")
                }
                if !body.isEmpty {
                    chunks.append(latexParagraphs(body))
                }
                let items = latexItemList(box.items)
                if !items.isEmpty {
                    chunks.append(items)
                }
                return chunks.joined(separator: "\n\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func templateBoxes(
        for kind: StructuredTemplateBoxKind,
        document: StructuredDocument
    ) -> [StructuredTemplateBox] {
        let explicitBoxes = document.templateBoxes
            .filter { $0.kind == kind }
            .map { box in
                StructuredTemplateBox(
                    kind: box.kind,
                    title: box.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    body: box.body.trimmingCharacters(in: .whitespacesAndNewlines),
                    items: box.items
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
            .filter { !$0.title.isEmpty || !$0.body.isEmpty || !$0.items.isEmpty }

        if !explicitBoxes.isEmpty {
            return explicitBoxes
        }

        switch kind {
        case .summary:
            let summary = document.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .summary, title: "Summary", body: summary)]
        case .key:
            let items = document.keyPoints
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .key, title: "Key Points", body: "", items: items)]
        case .meta:
            return []
        case .warning:
            return document.callouts
                .filter { $0.kind == .warning }
                .map {
                    StructuredTemplateBox(
                        kind: .warning,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: $0.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .filter { !$0.title.isEmpty || !$0.body.isEmpty }
        case .code:
            return []
        case .result:
            let items = document.actionItems
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .result, title: "Result", body: "", items: items)]
        case .exam:
            let items = document.reviewQuestions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .exam, title: "Review Questions", body: "", items: items)]
        case .checklist:
            let items = document.actionItems
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .checklist, title: "Checklist", body: "", items: items)]
        case .question:
            let cueItems = document.cueQuestions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let reviewItems = document.reviewQuestions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var seen: Set<String> = []
            let items = (cueItems + reviewItems).filter { seen.insert($0).inserted }
            guard !items.isEmpty else { return [] }
            return [StructuredTemplateBox(kind: .question, title: "Questions", body: "", items: items)]
        case .explanation:
            return document.callouts
                .filter { $0.kind == .note }
                .map {
                    StructuredTemplateBox(
                        kind: .explanation,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: $0.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .filter { !$0.title.isEmpty || !$0.body.isEmpty }
        case .example:
            return document.callouts
                .filter { $0.kind == .example }
                .map {
                    StructuredTemplateBox(
                        kind: .example,
                        title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: $0.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .filter { !$0.title.isEmpty || !$0.body.isEmpty }
        }
    }

    private static func latexParagraphs(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { latexEscaped(String($0)) }
            .joined(separator: "\n")
    }

    private static func latexItemList(_ items: [String]) -> String {
        guard !items.isEmpty else { return "" }
        let body = items
            .map { "\\item \(latexEscaped($0))" }
            .joined(separator: "\n")
        return "\\begin{itemize}\n\(body)\n\\end{itemize}"
    }

    private static func latexEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\textbackslash{}")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "~", with: "\\textasciitilde{}")
            .replacingOccurrences(of: "^", with: "\\textasciicircum{}")
    }
}

enum LatexProjectTemplateImporter {
    static func importTemplateProject(from url: URL) throws -> TemplateImportReview {
        let project = try loadProject(from: url)
        guard let mainSource = project.mainFileText else {
            throw LatexProjectError.mainFileIsNotUTF8("The selected main TeX file could not be decoded as UTF-8.")
        }

        let baseReview = makeBaseReview(from: mainSource)
        let slotted = slotifyMainSource(mainSource)
        let projectSource = LatexProjectSource(
            mainFilePath: project.mainFilePath,
            compiler: project.compiler,
            files: project.files,
            slotBindings: slotted.bindings
        ).updatingMainFile(text: slotted.source)

        var review = baseReview
        review.latexProjectSource = projectSource
        return review
    }

    private static func makeBaseReview(from source: String) -> TemplateImportReview {
        if let review = try? LatexTemplateImporter.importTemplate(from: source) {
            return review
        }

        let fallbackFingerprint = SourceFingerprint(
            palette: SourcePalette(
                accentHex: "#165FCA",
                surfaceHex: "#F6F9FF",
                namedColors: [:]
            ),
            boxStyles: [],
            headingSystem: source.contains("\\section{") ? .academicStructured : .simpleDocument,
            recurringSections: [],
            geometry: LatexGeometryHints()
        )
        let templateName = titleFromSource(source) ?? "Imported LaTeX Template"
        return TemplateImportReview(
            source: source,
            fingerprint: fallbackFingerprint,
            inferredArchetype: .technicalNote,
            templatePack: TemplatePackDefaults.importedPack(
                archetype: .technicalNote,
                fingerprint: fallbackFingerprint,
                suggestedName: templateName
            ),
            latexProjectSource: nil
        )
    }

    private static func loadProject(from url: URL) throws -> LatexProjectSource {
        var cleanupDirectory: URL?
        let directoryURL: URL
        let preferredMainFilePath: String?

        if url.hasDirectoryPath {
            directoryURL = url
            preferredMainFilePath = nil
        } else if url.pathExtension.lowercased() == "zip" {
            let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            try unzipProjectArchive(at: url, to: tempDirectory)
            cleanupDirectory = tempDirectory
            directoryURL = tempDirectory
            preferredMainFilePath = nil
        } else if url.pathExtension.lowercased() == "tex" {
            directoryURL = url.deletingLastPathComponent()
            preferredMainFilePath = url.lastPathComponent
        } else {
            throw LatexProjectError.unsupportedProject("Choose a `.tex` file, a LaTeX project folder, or a `.zip` exported from your template files.")
        }

        defer {
            if let cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanupDirectory)
            }
        }

        let files = try loadProjectFiles(from: directoryURL)
        let mainFilePath = try resolveMainFilePath(files: files, preferredPath: preferredMainFilePath)
        let compiler = detectCompiler(from: files.first(where: { $0.path == mainFilePath })?.textContents ?? "")
        return LatexProjectSource(
            mainFilePath: mainFilePath,
            compiler: compiler,
            files: files,
            slotBindings: []
        )
    }

    private static func loadProjectFiles(from directoryURL: URL) throws -> [LatexProjectFile] {
        let baseComponents = directoryURL.standardizedFileURL.pathComponents
        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var files: [LatexProjectFile] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = fileURL.standardizedFileURL.pathComponents
                .dropFirst(baseComponents.count)
                .joined(separator: "/")
            files.append(LatexProjectFile(path: relativePath, data: try Data(contentsOf: fileURL)))
        }

        guard !files.isEmpty else {
            throw LatexProjectError.unsupportedProject("The selected location did not contain any files.")
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func resolveMainFilePath(
        files: [LatexProjectFile],
        preferredPath: String?
    ) throws -> String {
        let texFiles = files.filter { $0.path.lowercased().hasSuffix(".tex") }
        guard !texFiles.isEmpty else {
            throw LatexProjectError.missingMainFile("No `.tex` file was found in the selected project.")
        }

        if let preferredPath {
            let normalized = preferredPath.replacingOccurrences(of: "\\", with: "/")
            if texFiles.contains(where: { $0.path == normalized }) {
                return normalized
            }
        }

        if texFiles.count == 1, let path = texFiles.first?.path {
            return path
        }

        let priorityNames = ["main.tex", "index.tex", "template.tex"]
        if let preferred = texFiles.first(where: { file in
            priorityNames.contains((file.path as NSString).lastPathComponent.lowercased())
        }) {
            return preferred.path
        }

        let documentClassFiles = texFiles.filter {
            $0.textContents?.contains("\\documentclass") == true
        }
        if documentClassFiles.count == 1, let path = documentClassFiles.first?.path {
            return path
        }

        throw LatexProjectError.missingMainFile(
            "Could not determine the main `.tex` file automatically. Keep one main file in the project or name it `main.tex`."
        )
    }

    private static func detectCompiler(from source: String) -> LatexCompilerProfile {
        let lowered = source.lowercased()
        if lowered.contains("!tex program = xelatex") || lowered.contains("fontspec") || lowered.contains("xeCJK".lowercased()) || lowered.contains("ctex") {
            return .xelatex
        }
        if lowered.contains("!tex program = pdflatex") {
            return .pdflatex
        }
        return .xelatex
    }

    private static func unzipProjectArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", archiveURL.path, "-d", destinationURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LatexProjectError.unsupportedProject("Could not unzip the selected LaTeX project archive.")
        }
    }

    private static func titleFromSource(_ source: String) -> String? {
        let pattern = #"\\title\{([\s\S]*?)\}"#
        let matches = source.matchingGroups(pattern: pattern)
        let trimmed = matches.first?.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func slotifyMainSource(_ source: String) -> (source: String, bindings: [LatexProjectSlotBinding]) {
        var updated = source
        var bindings: [LatexProjectSlotBinding] = []

        if replaceTitleCommand(in: &updated, token: "{{notescurator.title}}") {
            bindings.append(LatexProjectSlotBinding(token: "{{notescurator.title}}", field: .title))
        }

        if replaceFirstEnvironmentBody(in: &updated, matchingNames: ["key"], token: "{{notescurator.key_points}}") {
            bindings.append(LatexProjectSlotBinding(token: "{{notescurator.key_points}}", field: .keyPoints))
        }

        if replaceFirstSectionBody(
            in: &updated,
            matchingTitles: ["summary", "overview", "abstract"],
            token: "{{notescurator.summary}}"
        ) {
            bindings.append(LatexProjectSlotBinding(token: "{{notescurator.summary}}", field: .summary))
        }

        if replaceFirstSectionBody(
            in: &updated,
            matchingTitles: ["action items", "next steps", "todo"],
            token: "{{notescurator.action_items}}"
        ) {
            bindings.append(LatexProjectSlotBinding(token: "{{notescurator.action_items}}", field: .actionItems))
        }

        if replaceFirstGenericSectionBody(
            in: &updated,
            excludingTitles: ["summary", "overview", "abstract", "action items", "next steps", "todo"],
            token: "{{notescurator.sections}}"
        ) {
            bindings.append(LatexProjectSlotBinding(token: "{{notescurator.sections}}", field: .sections))
        }

        if bindings.contains(where: { $0.field == .summary }) == false {
            injectBeforeEndDocument(
                """
                \\section{Summary}
                {{notescurator.summary}}
                """,
                into: &updated
            )
            bindings.append(LatexProjectSlotBinding(token: "{{notescurator.summary}}", field: .summary))
        }

        if bindings.contains(where: { $0.field == .sections }) == false {
            injectBeforeEndDocument(
                """
                \\section{Details}
                {{notescurator.sections}}
                """,
                into: &updated
            )
            bindings.append(LatexProjectSlotBinding(token: "{{notescurator.sections}}", field: .sections))
        }

        return (updated, bindings)
    }

    private static func replaceTitleCommand(in source: inout String, token: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\\title\{([\s\S]*?)\}"#) else { return false }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              let wholeRange = Range(match.range(at: 0), in: source) else {
            return false
        }
        source.replaceSubrange(wholeRange, with: "\\title{\(token)}")
        return true
    }

    private static func replaceFirstEnvironmentBody(
        in source: inout String,
        matchingNames keywords: [String],
        token: String
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\\begin\{([^}]+)\}"#) else {
            return false
        }

        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: nsRange) {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let beginRange = Range(match.range(at: 0), in: source) else {
                continue
            }

            let name = String(source[nameRange])
            guard keywords.contains(where: name.lowercased().contains) else { continue }

            let bodyStart = source[beginRange.upperBound...].firstIndex(of: "\n").map { source.index(after: $0) } ?? beginRange.upperBound
            let endToken = "\\end{\(name)}"
            guard let endRange = source.range(of: endToken, range: bodyStart..<source.endIndex) else {
                continue
            }

            source.replaceSubrange(bodyStart..<endRange.lowerBound, with: token + "\n")
            return true
        }
        return false
    }

    private static func replaceFirstSectionBody(
        in source: inout String,
        matchingTitles keywords: [String],
        token: String
    ) -> Bool {
        replaceSectionBody(
            in: &source,
            token: token
        ) { title in
            let lowered = title.lowercased()
            return keywords.contains(where: lowered.contains)
        }
    }

    private static func replaceFirstGenericSectionBody(
        in source: inout String,
        excludingTitles excludedKeywords: [String],
        token: String
    ) -> Bool {
        replaceSectionBody(
            in: &source,
            token: token
        ) { title in
            let lowered = title.lowercased()
            return excludedKeywords.contains(where: lowered.contains) == false
        }
    }

    private static func replaceSectionBody(
        in source: inout String,
        token: String,
        matcher: (String) -> Bool
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\\section\*?\{([^}]+)\}"#) else { return false }

        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: nsRange)
        for (index, match) in matches.enumerated() {
            guard let titleRange = Range(match.range(at: 1), in: source),
                  matcher(String(source[titleRange])) else {
                continue
            }

            guard let bodyStart = Range(NSRange(location: match.range.location + match.range.length, length: 0), in: source)?.lowerBound else {
                continue
            }

            let nextSectionLocation = index + 1 < matches.count ? matches[index + 1].range.location : nil
            let endDocumentLocation = source.range(of: "\\end{document}")?.lowerBound.utf16Offset(in: source)
            let bodyEndLocation = [nextSectionLocation, endDocumentLocation, source.utf16.count]
                .compactMap { $0 }
                .min() ?? source.utf16.count

            guard let bodyEnd = Range(NSRange(location: bodyEndLocation, length: 0), in: source)?.lowerBound,
                  bodyStart <= bodyEnd else {
                continue
            }

            let originalBody = String(source[bodyStart..<bodyEnd])
            if let environmentRange = originalBody.range(of: "\\begin{") {
                let environmentStart = source.index(bodyStart, offsetBy: originalBody.distance(from: originalBody.startIndex, to: environmentRange.lowerBound))
                source.replaceSubrange(bodyStart..<environmentStart, with: "\n\(token)\n")
            } else {
                source.replaceSubrange(bodyStart..<bodyEnd, with: "\n\(token)\n")
            }
            return true
        }
        return false
    }

    private static func injectBeforeEndDocument(_ block: String, into source: inout String) {
        if let range = source.range(of: "\\end{document}") {
            source.insert(contentsOf: "\n\n\(block)\n", at: range.lowerBound)
        } else {
            source.append("\n\n\(block)\n")
        }
    }
}

private extension String {
    func matchingGroups(pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { groupIndex in
                guard let range = Range(match.range(at: groupIndex), in: self) else { return nil }
                return String(self[range])
            }
        }
    }
}

extension DraftVersion {
    func latexProjectForExport() -> LatexProjectSource? {
        guard let data = structuredDoc.exportMetadata.contentTemplateLatexProjectData else {
            return nil
        }
        return try? JSONDecoder().decode(LatexProjectSource.self, from: data)
    }

    func renderedLatexMainFile() throws -> String? {
        guard let project = latexProjectForExport() else { return nil }
        return try LatexProjectRenderer.renderMainFile(project: project, document: structuredDoc)
    }
}
