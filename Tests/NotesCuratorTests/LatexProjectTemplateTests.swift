import Foundation
import Testing
@testable import NotesCurator

struct LatexProjectTemplateTests {
    @Test
    func latexProjectTemplateKeepsProjectFilesAsSourceOfTruth() throws {
        let project = LatexProjectSource(
            mainFilePath: "main.tex",
            compiler: .xelatex,
            files: [
                LatexProjectFile.text(
                    path: "main.tex",
                    contents: sampleLatexMainSource
                ),
                LatexProjectFile.text(
                    path: "theme/custom.sty",
                    contents: "\\ProvidesPackage{custom}\n"
                )
            ],
            slotBindings: [
                LatexProjectSlotBinding(token: "{{notescurator.summary}}", field: .summary)
            ]
        )

        let template = Template.latexProject(
            project,
            scope: .user,
            name: "Physics Notes",
            subtitle: "Imported",
            templateDescription: "Full TeX project",
            goalType: .structuredNotes
        )

        let decoded = try #require(template.latexProjectSource())
        #expect(template.format == .latexProject)
        #expect(decoded.mainFilePath == "main.tex")
        #expect(decoded.files.count == 2)
        #expect(decoded.mainFileText?.contains("\\documentclass") == true)
        #expect(template.latexAuthoringSource?.contains("\\begin{document}") == true)
    }

    @Test
    func latexProjectImportPreservesLayoutWhileInjectingStructuredSlots() throws {
        let projectDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: projectDirectory) }

        try sampleLatexMainSource.write(
            to: projectDirectory.appendingPathComponent("main.tex"),
            atomically: true,
            encoding: .utf8
        )
        try "\\ProvidesPackage{brand}\n".write(
            to: projectDirectory.appendingPathComponent("brand.sty"),
            atomically: true,
            encoding: .utf8
        )

        let review = try LatexProjectTemplateImporter.importTemplateProject(from: projectDirectory)
        let project = try #require(review.latexProjectSource)
        let mainFile = try #require(project.mainFileText)

        #expect(project.mainFilePath == "main.tex")
        #expect(mainFile.contains("\\newtcolorbox{KeyBox}"))
        #expect(mainFile.contains("{{notescurator.summary}}"))
        #expect(mainFile.contains("{{notescurator.key_points}}"))
        #expect(mainFile.contains("{{notescurator.sections}}"))
        #expect(review.templatePack.identity.name == "Imported Physics Notes")
    }

    @Test
    func latexProjectRendererFillsStructuredContentWithoutChangingWrappers() throws {
        let project = LatexProjectSource(
            mainFilePath: "main.tex",
            compiler: .xelatex,
            files: [
                LatexProjectFile.text(
                    path: "main.tex",
                    contents: """
                    \\documentclass{article}
                    \\usepackage[most]{tcolorbox}
                    \\newtcolorbox{KeyBox}[1]{title=#1}
                    \\begin{document}
                    \\section{Summary}
                    {{notescurator.summary}}
                    \\begin{KeyBox}{Key Points}
                    {{notescurator.key_points}}
                    \\end{KeyBox}
                    \\section{Details}
                    {{notescurator.sections}}
                    \\end{document}
                    """
                )
            ],
            slotBindings: [
                LatexProjectSlotBinding(token: "{{notescurator.summary}}", field: .summary),
                LatexProjectSlotBinding(token: "{{notescurator.key_points}}", field: .keyPoints),
                LatexProjectSlotBinding(token: "{{notescurator.sections}}", field: .sections)
            ]
        )

        let rendered = try LatexProjectRenderer.renderMainFile(
            project: project,
            document: sampleStructuredDocument
        )

        #expect(rendered.contains("\\begin{KeyBox}{Key Points}"))
        #expect(rendered.contains("A compact summary for the rendered note."))
        #expect(rendered.contains("\\item Revenue up 24\\%"))
        #expect(rendered.contains("\\subsection*{Context}"))
        #expect(rendered.contains("The team needs a cleaner rollout sequence."))
    }

    @Test
    func latexProjectRendererDropsOptionalBoxesWhenNoMatchingContentExists() throws {
        let project = LatexProjectSource(
            mainFilePath: "main.tex",
            compiler: .xelatex,
            files: [
                LatexProjectFile.text(
                    path: "main.tex",
                    contents: """
                    \\documentclass{article}
                    \\begin{document}
                    % notescurator.optional.begin:warningBoxes
                    \\begin{WarningBox}{Warnings}
                    {{notescurator.warning_boxes}}
                    \\end{WarningBox}
                    % notescurator.optional.end:warningBoxes
                    \\section{Summary}
                    {{notescurator.summary}}
                    \\end{document}
                    """
                )
            ],
            slotBindings: [
                LatexProjectSlotBinding(token: "{{notescurator.warning_boxes}}", field: .warningBoxes),
                LatexProjectSlotBinding(token: "{{notescurator.summary}}", field: .summary)
            ]
        )

        let rendered = try LatexProjectRenderer.renderMainFile(
            project: project,
            document: StructuredDocument.fixture(
                title: "Lean Brief",
                summary: "Only the summary should remain here.",
                sections: [],
                actionItems: [],
                exportMetadata: ExportMetadata(
                    contentTemplateName: "Formal Document",
                    visualTemplateName: "Oceanic Blue",
                    preferredFormat: .pdf
                )
            )
        )

        #expect(rendered.contains("\\begin{WarningBox}") == false)
        #expect(rendered.contains("Only the summary should remain here.") == true)
    }

    @Test
    func latexProjectCompilerUsesConfiguredToolchainAndProducesPDF() throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let recorder = RecordingLatexCommandExecutor()
        let compiler = LatexProjectCompiler(
            executor: recorder,
            locator: StubLatexToolLocator(
                tools: [
                    .xelatex: URL(fileURLWithPath: "/Library/TeX/texbin/xelatex")
                ]
            )
        )

        let project = LatexProjectSource(
            mainFilePath: "main.tex",
            compiler: .xelatex,
            files: [
                LatexProjectFile.text(path: "main.tex", contents: sampleLatexMainSource)
            ],
            slotBindings: []
        )

        let pdfURL = try compiler.compile(project: project, in: workingDirectory)

        let commands = recorder.snapshot()
        #expect(commands.count == 1)
        #expect(commands.first?.executableURL.path == "/Library/TeX/texbin/xelatex")
        #expect(commands.first?.arguments.contains("main.tex") == true)
        #expect(pdfURL.pathExtension == "pdf")
        #expect(FileManager.default.fileExists(atPath: pdfURL.path))
    }

    @Test
    func latexProjectCompilerFallsBackToPDFLaTeXWhenXeLaTeXIsUnavailable() throws {
        let workingDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let recorder = RecordingLatexCommandExecutor()
        let compiler = LatexProjectCompiler(
            executor: recorder,
            locator: StubLatexToolLocator(
                tools: [
                    .pdflatex: URL(fileURLWithPath: "/Library/TeX/texbin/pdflatex")
                ]
            )
        )

        let project = LatexProjectSource(
            mainFilePath: "main.tex",
            compiler: .xelatex,
            files: [
                LatexProjectFile.text(
                    path: "main.tex",
                    contents: """
                    \\documentclass{article}
                    \\begin{document}
                    English-only template
                    \\end{document}
                    """
                )
            ],
            slotBindings: []
        )

        let pdfURL = try compiler.compile(project: project, in: workingDirectory)

        let commands = recorder.snapshot()
        #expect(commands.count == 1)
        #expect(commands.first?.executableURL.lastPathComponent == "pdflatex")
        #expect(pdfURL.pathExtension == "pdf")
    }
}

private let sampleLatexMainSource = """
\\documentclass{article}
\\usepackage[most]{tcolorbox}
\\newtcolorbox{KeyBox}[1]{title=#1}
\\title{Imported Physics Notes}
\\begin{document}
\\maketitle
\\section{Summary}
Original summary text
\\begin{KeyBox}{Key Points}
Original key point
\\end{KeyBox}
\\section{Details}
Original body text
\\end{document}
"""

private let sampleStructuredDocument = StructuredDocument(
    title: "Project Strategy",
    summary: "A compact summary for the rendered note.",
    keyPoints: ["Revenue up 24%", "Brand system needs revision"],
    sections: [
        StructuredSection(title: "Context", body: "The team needs a cleaner rollout sequence.")
    ],
    actionItems: ["Assign owners"],
    imageSlots: [],
    exportMetadata: ExportMetadata(
        contentTemplateName: "Physics Notes",
        visualTemplateName: "Oceanic Blue",
        preferredFormat: .pdf
    )
)

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private struct RecordedLatexCommand: Equatable {
    var executableURL: URL
    var arguments: [String]
    var currentDirectoryURL: URL
}

private final class RecordingLatexCommandExecutor: LatexCommandExecuting, @unchecked Sendable {
    private var commands: [RecordedLatexCommand] = []
    private let lock = NSLock()

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) throws -> LatexCommandResult {
        lock.lock()
        commands.append(
            RecordedLatexCommand(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL
            )
        )
        lock.unlock()

        let pdfURL = currentDirectoryURL.appendingPathComponent("main.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: pdfURL)
        return LatexCommandResult(terminationStatus: 0, standardOutput: Data(), standardError: Data())
    }

    func snapshot() -> [RecordedLatexCommand] {
        lock.lock()
        defer { lock.unlock() }
        return commands
    }
}

private struct StubLatexToolLocator: LatexToolLocating {
    var tools: [LatexCompilerProfile: URL]

    func toolURL(for compiler: LatexCompilerProfile) -> URL? {
        tools[compiler]
    }
}
